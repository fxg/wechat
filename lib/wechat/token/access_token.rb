module Wechat
  module Token
    module AccessToken
      def self.token(component_appid, authorizer_appid, tries = 2)
        Wechat.redis.hget("wechat_authorizer_access_token_#{component_appid}_#{authorizer_appid}", 'authorizer_access_token')
      rescue
        retry unless (tries -= 1).zero?
      end

      def self.component_access_token(component_appid, tries = 2)
        Wechat.redis.hget("wechat_component_access_token_#{component_appid}", 'component_access_token')
      rescue
        retry unless (tries -= 1).zero?
      end
    end
  end
end
