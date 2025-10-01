require 'ferrum'
require 'nokogiri'
require 'uri'

class MarriottScraperFerrum
  SEARCH_URL = "https://www.marriott.com/search/findHotels.mi"
  OVERVIEW_URL_TEMPLATE = "https://www.marriott.com/en-us/hotels/%{marsha}-%{slug}/overview/"
  WAIT_TIMEOUT      = 40    
  WAIT_SLEEP        = 2  
  FETCH_RETRIES     = 3
  FETCH_RETRY_SLEEP = 6

  def initialize(city:, country:, check_in:, check_out:, headless: true)
    @city      = city
    @country   = country
    @check_in  = check_in
    @check_out = check_out
    @headless  = headless
  end

  def run
    browser = Ferrum::Browser.new(headless: @headless, timeout: 60)
    puts "🔎 Navigating to: #{search_url}"
    browser.goto(search_url)
    wait_for_results(browser)
    hotel_data = extract_hotels(browser)
    print_hotels_with_details(browser, hotel_data)
    browser.quit
  end

  private

  def search_url
    params = {
      "destinationAddress.mainText" => @city,
      "destinationAddress.country"  => @country,
      "destinationAddress.city"     => @city,
      "fromDate"                    => @check_in,
      "toDate"                      => @check_out,
      "deviceType"                  => "desktop-web",
      "view"                        => "list"
    }
    uri = URI(SEARCH_URL)
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  def wait_for_results(browser)
    timeout = Time.now + WAIT_TIMEOUT
    attempt = 0
    loop do
      attempt += 1
      spinner = browser.at_css(".loading-spinner")
      cards = browser.css("div.property-card")
      puts "Waiting... attempt #{attempt} (#{cards.size} hotel cards found)"
      break if spinner.nil? && cards.size > 0
      raise "Timeout after #{attempt} tries" if Time.now > timeout
      sleep WAIT_SLEEP
    end
  end

  def extract_hotels(browser)
    browser.css("div.property-card").map.with_index(1) do |card, idx|
      attrs = Hash[*card.description["attributes"]]
      name  = card.at_css("button.title-container")&.text&.strip
      lat, lon, marsha = nil
      if attrs['data-property']
        begin
          prop = JSON.parse(attrs['data-property'])
          lat    = prop["lat"]
          lon    = prop["long"]
          marsha = prop["marshacode"]
        rescue JSON::ParserError => e
          puts "Failed to parse data-property JSON for card #{idx}: #{e.message}"
        end
      end

      next unless name && marsha
      { index: idx, name: name, marsha: marsha, lat: lat, lon: lon }
    end.compact
  end

  def print_hotels_with_details(browser, hotel_data)
    hotel_data.each do |hotel|
      overview_url = build_overview_url(hotel[:marsha], hotel[:name])
      html = fetch_html_with_retry(browser, overview_url)
      if html
        info = extract_address_and_phone(html)
        puts " [#{hotel[:index]}] #{hotel[:name]}"
        puts "    Code / Marsha: #{hotel[:marsha]}"
        puts "    Latitude: #{hotel[:lat]}"
        puts "    Longitude: #{hotel[:lon]}"
        puts "    Address: #{info[:address]}"
        puts "    Phone: #{info[:phone]}"
        break if hotel[:index] == 10
      else
        puts "Failed to fetch overview for #{hotel[:name]} (#{overview_url})"
      end
      puts "-" * 60
    end
  end

  def build_overview_url(marsha, name)
    slug = name.downcase.strip.gsub(/[^\w\s-]/, '').gsub(/\s+/, '-').gsub(/-+/, '-')
    OVERVIEW_URL_TEMPLATE % { marsha: marsha, slug: slug }
  end

  def fetch_html_with_retry(browser, url, max_retries = FETCH_RETRIES, delay = FETCH_RETRY_SLEEP)
    attempts = 0
    begin
      attempts += 1
      browser.goto(url)
      return browser.body
    rescue Ferrum::TimeoutError, Ferrum::DeadBrowserError => e
      puts "Timeout fetching URL #{url}: #{e.message}. Retry #{attempts}/#{max_retries}..."
      sleep(delay) if attempts < max_retries
      retry if attempts < max_retries
    rescue StandardError => e
      puts "Error fetching URL #{url}: #{e.message}. Retry #{attempts}/#{max_retries}..."
      sleep(delay) if attempts < max_retries
      retry if attempts < max_retries
    end
    nil
  end

  def extract_address_and_phone(html)
    doc = Nokogiri::HTML(html)
    address_block = doc.at_css('.getting-here__left-body')
    phone_block   = doc.at_css('.getting-here__left-anchor a[href^="tel:"]')
    address = address_block&.css('p')&.[](1)&.text&.strip
    phone   = phone_block&.text&.strip
    { address: address, phone: phone }
  end
end

# Usage
scraper = MarriottScraperFerrum.new(
  city: 'Delhi',
  country: 'IN',
  check_in: '2025-09-29',
  check_out: '2025-09-30',
  headless: false
)
scraper.run
