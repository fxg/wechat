module Wechat
  module Token
    class AccessTokenBase
      attr_reader :access_token, :token_life_in_seconds, :got_token_at

      def initialize
        @random_generator = Random.new
      end

      def token
        # Possible two worker running, one worker refresh token, other unaware, so must read every time
        read_token_from_store
        refresh if remain_life_seconds < @random_generator.rand(30..3 * 60)
        access_token
      end

      protected

      def read_token_from_store
        # td = read_token
        @token_life_in_seconds = redis.hget("wechat_authorizer_access_token_#{component_appid}_#{authorizer_appid}",
        'expires_in').to_i
        #td.fetch('token_expires_in').to_i
        @got_token_at = redis.hget("wechat_authorizer_access_token_#{component_appid}_#{authorizer_appid}", 'got_token_at').to_i
        @access_token = redis.hget("wechat_authorizer_access_token_#{component_appid}_#{authorizer_appid}", 'authorizer_access_token') # return access_token same time
      rescue JSON::ParserError, Errno::ENOENT, KeyError, TypeError
        refresh
      end

      def remain_life_seconds
        token_life_in_seconds - (Time.now.to_i - got_token_at)
      end
    end
  end
end
