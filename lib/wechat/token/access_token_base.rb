module Wechat
  module Token
    class AccessTokenBase
      attr_reader :component_appid, :authorizer_appid, :access_token

      def initialize(component_appid, authorizer_appid)
        @component_appid = component_appid
        @authorizer_appid = authorizer_appid
        @random_generator = Random.new
      end

      def token(tries = 2)
        @access_token = Wechat.redis.hget("wechat_authorizer_access_token_#{component_appid}_#{authorizer_appid}", 'authorizer_access_token')
      rescue
        retry unless (tries -= 1).zero?
      end
    end
  end
end
