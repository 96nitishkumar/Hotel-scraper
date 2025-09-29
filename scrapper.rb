require 'httparty'
require 'nokogiri'
require 'json'
require 'uri'
require 'logger'

class MarriottHotelScraper
    def initialize
        @logger = Logger.new(STDOUT)
        @logger.level = Logger::INFO
        @logger.formatter = proc do |severity, datetime, progname, msg|
        "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
        end
    end

  # ==========================================
  #       Marriott Hotels HTML Scraping
  # ==========================================
  

    def scrape_marriott_locations
        @logger.info("Starting Marriott hotel locations scraping...")
        
        base_url = "https://www.marriott.com"
        hotels = []

        begin
            main_page = fetch_html_with_retry("#{base_url}/default.mi")
            return [] unless main_page

            hotel_links = extract_marriott_hotel_links(main_page, base_url)

            @logger.info("Found #{hotel_links.length} hotel pages to scrape")

            hotel_links.each_with_index do |link, index|
            @logger.info("Scraping hotel #{index + 1}/#{hotel_links.length}: #{link}")

            begin
                hotel_data = scrape_single_marriott_hotel(link)
                hotels << hotel_data if hotel_data

                sleep(2)
            rescue => e
                @logger.error("Failed to scrape #{link}: #{e.message}")
            end

            break if index >= 10
            end

            @logger.info("Completed Marriott scraping. Found #{hotels.length} hotels")
        rescue => e
            @logger.error("Marriott scraping failed: #{e.message}")
        end

        hotels
    end

  
  private
  
    def extract_marriott_hotel_links(doc, base_url)
        links = []
        location_links = doc.css('a[href*="hotels"]', 'a[href*="search"]', 'a[href*="locations"]')

        location_links.each do |link|
            href = link['href']
            next unless href
            
            full_url = href.start_with?('http') ? href : "#{base_url}#{href}"
            links << full_url if full_url.match(%r{/overview/?\z})
        end
        
        links.uniq
    end
  
    def scrape_single_marriott_hotel(url)
        doc = fetch_html_with_retry(url)
        return nil unless doc
        hotel_data = {
        url: url,
        name: extract_marriott_name_and_address(doc).first,
        phone: extract_marriott_phone(doc),
        email: extract_marriott_email(doc),
        address: extract_marriott_name_and_address(doc).last,
        latitude: extract_marriott_latitude(doc),
        longitude: extract_marriott_longitude(doc)
        }
        
        @logger.debug("Extracted: #{hotel_data}")
        hotel_data
    end
  
    def extract_marriott_name_and_address(doc)
        div = doc.at_css("div.getting-here__left-body.mb-xl-5.mb-3")
        return [nil, nil] unless div

        paragraphs = div.css("p")
        name = paragraphs[0]&.text&.strip
        address = paragraphs[1]&.text&.strip

        [name, address]
    end

    def extract_marriott_phone(doc)

        full_text = doc.text
        phone_regex = /(\+\d{1,3}[\s\-]?\d{3}[\s\-]?\d{6})/

        match = full_text.match(phone_regex)
        match ? match[1].strip : nil
    end
    
    def extract_marriott_email(doc)
        email_selectors = [
        '.contact-email',
        '.hotel-email',
        '[data-testid="email"]',
        'a[href^="mailto:"]'
        ]
        
        email_selectors.each do |selector|
        element = doc.at_css(selector)
        if element
            email_text = element.text.strip
            email_match = email_text.match(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/)
            return email_match[0] if email_match
        end
        end
        
        all_text = doc.text
        email_match = all_text.match(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b/)
        return email_match[0] if email_match
        
        nil
    end
  
  
    def extract_marriott_latitude(doc)
        extract_coordinate(doc, 'latitude')
    end
    
    def extract_marriott_longitude(doc)
        extract_coordinate(doc, 'longitude')
    end
  
    def extract_coordinate(doc, coord_type)
        json_ld = doc.css('script[type="application/ld+json"]')
        json_ld.each do |script|
        begin
            data = JSON.parse(script.text)
            if data['geo'] && data['geo'][coord_type]
            return data['geo'][coord_type].to_f
            end
        rescue JSON::ParserError
            next
        end
        end
        
        element = doc.at_css("[data-#{coord_type}]")
        return element["data-#{coord_type}"].to_f if element
        
        meta = doc.at_css("meta[name='#{coord_type}'], meta[property='#{coord_type}']")
        return meta['content'].to_f if meta
        
        nil
    end

   def fetch_html_with_retry(url, max_retries = 3, delay = 6, timeout = 15)
    attempts = 0
    
    # Use different User-Agents to avoid detection
    user_agents = [
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
    ]
    
    begin
      attempts += 1
      @logger.debug("Fetching #{url} (attempt #{attempts})")
      
      # Add delay between requests to avoid rate limiting
      sleep(rand(2..4)) if attempts > 1
      
      response = HTTParty.get(url, 
        timeout: timeout,
        headers: {
          'User-Agent' => user_agents.sample,
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
          'Accept-Language' => 'en-US,en;q=0.9',
          'Accept-Encoding' => 'gzip, deflate, br',
          'Cache-Control' => 'no-cache',
          'DNT' => '1',
          'Connection' => 'keep-alive',
          'Upgrade-Insecure-Requests' => '1',
          'Sec-Fetch-Dest' => 'document',
          'Sec-Fetch-Mode' => 'navigate',
          'Sec-Fetch-Site' => 'none',
          'Sec-Fetch-User' => '?1'
        }
      )
      
      if response.success?
        @logger.debug("Successfully fetched #{url} (#{response.code})")
        return Nokogiri::HTML(response.body)
      else
        raise "HTTP #{response.code}: #{response.message}"
      end
      
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      @logger.warn("Timeout fetching #{url}: #{e.message}. Retry #{attempts}/#{max_retries}")
      sleep(delay * attempts) if attempts < max_retries # Exponential backoff
      retry if attempts < max_retries
      
    rescue => e
      @logger.warn("Error fetching #{url}: #{e.message}. Retry #{attempts}/#{max_retries}")
      sleep(delay * attempts) if attempts < max_retries
      retry if attempts < max_retries
    end
    
    @logger.error("Failed to fetch #{url} after #{max_retries} attempts")
    nil
  end
end

# ==========================================
# MAIN EXECUTION
# ==========================================

  scraper = MarriottHotelScraper.new
  
  puts "=" * 60
  puts "ASSIGNMENT A: Marriott Hotels HTML Scraping"
  puts "=" * 60
  
  marriott_hotels = scraper.scrape_marriott_locations
  
  puts "\n MARRIOTT RESULTS:"
  marriott_hotels.each_with_index do |hotel, index|
    puts "\n#{index + 1}. #{hotel[:name] || 'Unknown Hotel'}"
    puts "   Phone: #{hotel[:phone] || 'N/A'}"
    puts "   Email: #{hotel[:email] || 'N/A'}"
    puts "   Address: #{hotel[:address] || 'N/A'}"
    puts "   Coordinates: #{hotel[:latitude]}, #{hotel[:longitude]}" if hotel[:latitude]
    puts "   URL: #{hotel[:url]}"

  end
  
  
  puts "\n" + "=" * 60
  puts "SUMMARY:"
  puts "Marriott Hotels: #{marriott_hotels.length} found"
  puts "=" * 60
