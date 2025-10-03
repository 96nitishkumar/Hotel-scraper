
require 'rspec'
require_relative './basic_scrapper'

RSpec.describe MarriottScraperFerrum do
  let(:browser_double) { instance_double(Ferrum::Browser) }
  let(:city) { 'Delhi' }
  let(:country) { 'IN' }
  let(:check_in) { '2025-09-29' }
  let(:check_out) { '2025-09-30' }
  let(:scraper) do
    described_class.new(
      city: city,
      country: country,
      check_in: check_in,
      check_out: check_out,
      headless: true
    )
  end

  describe "#search_url" do
    it "builds the expected Marriott search URL" do
      url = scraper.send(:search_url)
      expect(url).to include("destinationAddress.mainText=Delhi")
      expect(url).to include("destinationAddress.country=IN")
      expect(url).to include("fromDate=2025-09-29")
      expect(url).to include("toDate=2025-09-30")
    end
  end

  describe "#build_overview_url" do
    it "creates slug from hotel name and inserts marsha code" do
      url = scraper.send(:build_overview_url, "DELHI", "JW Marriott Hotel New Delhi Aerocity")
      expect(url).to match(/DELHI-jw-marriott-hotel-new-delhi-aerocity/)
    end
  end

  describe "#extract_address_and_phone" do
    it "extracts address and phone from html" do
      html = <<~HTML
        <div class="getting-here__left-body">
          <p>Getting Here</p>
          <p>Asset Area 4, Hospitality District, Delhi, 110037 India</p>
        </div>
        <div class="getting-here__left-anchor">
          <a href="tel:+911123456789">+91 11 2345 6789</a>
        </div>
      HTML
      info = scraper.send(:extract_address_and_phone, html)
      expect(info[:address]).to eq("Asset Area 4, Hospitality District, Delhi, 110037 India")
      expect(info[:phone]).to eq("+91 11 2345 6789")
    end
  end

  describe "#fetch_html_with_retry" do
    it "returns html on first try" do
      allow(browser_double).to receive(:goto).and_return(true)
      allow(browser_double).to receive(:body).and_return("<html>ok</html>")
      html = scraper.send(:fetch_html_with_retry, browser_double, "http://example.com", 2, 0)
      expect(html).to eq("<html>ok</html>")
    end

    it "retries on timeout, then returns nil on exceeding retries" do
      allow(browser_double).to receive(:goto).and_raise(Ferrum::TimeoutError)
      html = scraper.send(:fetch_html_with_retry, browser_double, "http://bad.com", 2, 0)
      expect(html).to be_nil
    end
  end

  describe "#extract_hotels" do
    it "parses hotel cards and extracts data" do
      fake_card = double(
        description: { "attributes" => ["data-property", '{"lat":28.61,"long":77.23,"marshacode":"DELHI"}'] },
        at_css: double(text: "JW Marriott Hotel New Delhi Aerocity")
      )
      allow(fake_card).to receive(:at_css).with("button.title-container").and_return(double(text: "JW Marriott Hotel New Delhi Aerocity"))
      allow(browser_double).to receive(:css).with("div.property-card").and_return([fake_card])

      hotels = scraper.send(:extract_hotels, browser_double)
      expect(hotels.first[:name]).to eq("JW Marriott Hotel New Delhi Aerocity")
      expect(hotels.first[:marsha]).to eq("DELHI")
    end
  end
end
