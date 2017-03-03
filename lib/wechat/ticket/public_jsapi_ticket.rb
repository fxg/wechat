require 'wechat/ticket/jsapi_base'

module Wechat
  module Ticket
    class PublicJsapiTicket < JsapiBase
      def refresh
        @access_ticket = Wechat.redis.hget("jsapi_ticket_key_#{component_appid}_#{authorizer_appid}", 'ticket')
      end
    end
  end
end
