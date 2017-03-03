require 'wechat/token/access_token_base'

module Wechat
  module Token
    class PublicAccessToken < AccessTokenBase
      def refresh
        @access_token = Wechat.redis.hget("wechat_authorizer_access_token_#{component_appid}_#{authorizer_appid}", 'authorizer_access_token')
      end
    end
  end
end
