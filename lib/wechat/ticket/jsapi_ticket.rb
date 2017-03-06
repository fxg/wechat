require 'digest/sha1'
require 'securerandom'

module Wechat
  module Ticket
    class JsapiTicket
      attr_reader :component_appid, :authorizer_appid, :oauth2_state, :access_ticket

      def initialize(component_appid, authorizer_appid)
        @component_appid = component_appid
        @authorizer_appid = authorizer_appid
        @random_generator = Random.new
      end

      def ticket(tries = 2)
        # Possible two worker running, one worker refresh ticket, other unaware, so must read every time
        @oauth2_state = SecureRandom.hex(16)
        @access_ticket = Wechat.redis.hget("jsapi_ticket_key_#{component_appid}_#{authorizer_appid}", 'ticket')
      rescue
        retry unless (tries -= 1).zero?
      end

      # Obtain the wechat jssdk config signature parameter and return below hash
      #  params = {
      #    noncestr: noncestr,
      #    timestamp: timestamp,
      #    jsapi_ticket: ticket,
      #    url: url,
      #    signature: signature
      #  }
      def signature(url)
        p "jsapi ticket: #{ticket}"
        params = {
          noncestr: SecureRandom.base64(16),
          timestamp: Time.now.to_i,
          jsapi_ticket: ticket,
          url: url
        }
        pairs = params.keys.sort.map do |key|
          "#{key}=#{params[key]}"
        end
        result = Digest::SHA1.hexdigest pairs.join('&')
        params.merge(signature: result)
      end
    end
  end
end
