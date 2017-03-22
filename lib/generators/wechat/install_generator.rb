module Wechat
  module Generators
    class InstallGenerator < Rails::Generators::Base
      desc 'Install Wechat support files'
      source_root File.expand_path('../templates', __FILE__)

      def copy_config
        template 'config/wechat.yml'
        template 'config/redis.yml'
      end

      def copy_wechat_redis_initializer
        template 'config/initializers/redis.rb'
        template 'config/initializers/wechat_redis_store.rb'
      end

      def copy_wechat_controller
        template 'app/controllers/wechats_controller.rb'
      end

      def add_redis_gem
        gem 'redis'
        gem 'redis-objects'
        gem 'connection_pool'
      end

      def add_wechat_route
        # route 'resource :wechat, only: [:show, :create]'
        route "get 'wx/:authorizer_appid/callback', to: 'wechats#show'"
        route  "post 'wx/:authorizer_appid/callback', to: 'wechats#create'"
        route "get 'wx/auth', to: 'wechats#auth_callback'"
        route "post 'wx/auth', to: 'wechats#auth'"
        route "get 'wechatauth/authorize_page'"
      end
    end
  end
end
