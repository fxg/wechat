module Wechat
  module Token
    class AccessToken
      # attr_reader :access_token, :component_access_token, :pre_auth_cod

      def initialize(component_appid, authorizer_appid = nil)
        @component_appid ||= component_appid
        @authorizer_appid ||= authorizer_appid
      end

      def token(tries = 2)
        Wechat.redis.hget("wechat_authorizer_access_token_#{@component_appid}_#{@authorizer_appid}", 'authorizer_access_token')
      rescue
        retry unless (tries -= 1).zero?
      end

      def component_access_token(tries = 2)
        Wechat.redis.hget("wechat_component_access_token_#{@component_appid}", 'component_access_token')
      rescue
        retry unless (tries -= 1).zero?
      end
    end
  end
end
