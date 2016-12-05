require 'twitter_ebooks'
require 'httparty'
require 'open-uri'

def format_number(number)
  number.to_s.reverse.gsub(/...(?=.)/,'\&,').reverse
end

MAPBOX_ACCESS_TOKEN = ''.freeze

STYLES = [
  'outdoors-v9',
  'satellite-v9',
  'satellite-streets-v9'
].freeze

class AeroPlanesBot < Ebooks::Bot
  def configure
    # Consumer details come from registering an app at https://dev.twitter.com/
    # Once you have consumer details, use "ebooks auth" for new access tokens
    self.consumer_key = '' # Your app consumer key
    self.consumer_secret = '' # Your app consumer secret

    # Range in seconds to randomize delay when bot.delay is called
    self.delay_range = 0..600
  end

  def get_something_to_tweet
    log 'Searching the sky...'

    plane_response = HTTParty.get "https://opensky-network.org/api/states/all"

    # wow this is surprisingly straightforward
    plane = plane_response['states'].select{
      |state| !state[1].empty? && !state[2].nil? && !state[5].nil? && !state[10].nil?
    }.sample

    # wow this API sucks but it's free so oh well
    callsign = plane[1].strip
    origin_country = plane[2]
    longitude = plane[5]
    latitude = plane[6]

    log "Found #{callsign}! Let's check out where it is..."

    altitude = plane[7]
    on_ground = plane[8]
    velocity = plane[9]
    heading = plane[10]

    location_response = HTTParty.get(
      "https://api.mapbox.com/geocoding/v5/mapbox.places/#{longitude},#{latitude}.json",
      query: {
        types: 'locality,region,country',
        limit: 1,
        access_token: MAPBOX_ACCESS_TOKEN
      }
    )

    parsed_location = JSON.parse(location_response)

    location_name = parsed_location['features'].select{
      |location| !location.nil? && !location['place_name'].nil? && !location['place_name'].empty?
    }.first['place_name'].gsub(/, #{origin_country}$/, '')

    log "Hey, it's at #{location_name}! Let's build a tweet..."

    altitude_text = "#{format_number(altitude.round)}m"

    tweet =  "#{callsign}"
    tweet += " from #{origin_country} is" if !origin_country.nil?
    tweet += " travelling at #{format_number((velocity * 3.6).round)}km/h" if !velocity.nil? && velocity > 50
    tweet += ", #{altitude_text} above #{location_name}" if !on_ground
    tweet += " on the ground at #{location_name}" if on_ground

    zoom = 5
    pitch = 0

    if !altitude.nil? then
      zoom = 15 - (altitude / 1300).round
    end

    if !velocity.nil? then
      pitch = 59 - (velocity / 54).round
    end

    image_url = "https://api.mapbox.com/styles/v1/mapbox/#{STYLES.sample}/static/#{longitude},#{latitude},#{zoom},#{heading},#{pitch}/558x380@2x?access_token=#{MAPBOX_ACCESS_TOKEN}"

    log "Downloading image from '#{image_url}'..."

    [tweet, open(image_url)]
  end

  def make_public_tweet
    text, image = get_something_to_tweet
    id = twitter.upload(image).to_s
    tweet(text, {media_ids: id})
  end

  def on_startup
    scheduler.every '24m' do
      delay do
        make_public_tweet
      end
    end
  end
end

AeroPlanesBot.new("aero_planes") do |bot|
  bot.access_token = "" # Token connecting the app to this account
  bot.access_token_secret = "" # Secret connecting the app to this account
end
