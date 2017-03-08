module Wechat
  module ApiLoader
    def self.with(options)
      account = options[:account] || :default
      c = ApiLoader.config(account)

      component_appid = options[:component_appid] || c.component_appid

      if component_appid
        Wechat::Api.new(component_appid, c.timeout, c.skip_verify_ssl)
      else
        puts <<-HELP
Need create ~/.wechat.yml with wechat appid and secret
or running at rails root folder so wechat can read config/wechat.yml
HELP
        exit 1
      end
    end

    @configs = nil

    def self.config(account = :default)
      account = :default if account.nil?
      @configs ||= loading_config!
      @configs[account.to_sym] || raise("Wechat configuration for #{account} is missing.")
    end

    private_class_method def self.loading_config!
      configs = config_from_file || config_from_environment

      configs.symbolize_keys!
      configs.each do |key, cfg|
        if cfg.is_a?(Hash)
          cfg.symbolize_keys!
        else
          raise "wrong wechat configuration format for #{key}"
        end
      end

      # if defined?(::Rails)
      #   configs.each do |_, cfg|
      #     cfg[:access_token] ||= Rails.root.try(:join, "tmp/access_token_#{cfg[:appid]}").try(:to_path)
      #     cfg[:jsapi_ticket] ||= Rails.root.try(:join, "tmp/jsapi_ticket_#{cfg[:component_appid]}").try(:to_path)
      #   end
      # end

      configs.each do |_, cfg|
        cfg[:timeout] ||= 20
        cfg[:have_session_class] = class_exists?('WechatSession')
      end

      # create config object using raw config data
      cfg_objs = {}
      configs.each do |account, cfg|
        cfg_objs[account] = OpenStruct.new(cfg)
      end
      cfg_objs
    end

    private_class_method def self.config_from_file
      if defined?(::Rails)
        config_file = ENV['WECHAT_CONF_FILE'] || Rails.root.join('config/wechat.yml')
        return resovle_config_file(config_file, Rails.env.to_s)
      else
        rails_config_file = ENV['WECHAT_CONF_FILE'] || File.join(Dir.getwd, 'config/wechat.yml')
        application_config_file = File.join(Dir.getwd, 'config/application.yml')
        home_config_file = File.join(Dir.home, '.wechat.yml')
        if File.exist?(rails_config_file)
          if File.exist?(application_config_file) && !defined?(::Figaro)
            require 'figaro'
            Figaro::Application.new(path: application_config_file).load
          end
          rails_env = ENV['RAILS_ENV'] || 'development'
          config = resovle_config_file(rails_config_file, rails_env)
          if config.present? && (default = config[:default]) && (default['component_appid'])
            puts "Using rails project #{ENV['WECHAT_CONF_FILE'] || "config/wechat.yml"} #{rails_env} setting..."
            return config
          end
        end
        if File.exist?(home_config_file)
          return resovle_config_file(home_config_file, nil)
        end
      end
    end

    private_class_method def self.resovle_config_file(config_file, env)
      if File.exist?(config_file)
        raw_data = YAML.load(ERB.new(File.read(config_file)).result)
        configs = {}
        if env
          # Process multiple accounts when env is given
          raw_data.each do |key, value|
            if key == env
              configs[:default] = value
            elsif m = /(.*?)_#{env}$/.match(key)
              configs[m[1].to_sym] = value
            end
          end
        else
          # Treat is as one account when env is omitted
          configs[:default] = raw_data
        end
        configs
      end
    end

    private_class_method def self.config_from_environment
      value = {
        component_appid: ENV['WECHAT_COMPONENT_APPID'],
        token: ENV['WECHAT_TOKEN'],
        encrypt_mode: true,
        timeout: ENV['WECHAT_TIMEOUT'],
        skip_verify_ssl: ENV['WECHAT_SKIP_VERIFY_SSL'],
        encoding_aes_key: ENV['WECHAT_ENCODING_AES_KEY'],
        trusted_domain_fullname: ENV['WECHAT_TRUSTED_DOMAIN_FULLNAME']}
      {default: value}
    end

    private_class_method def self.class_exists?(class_name)
      return Module.const_get(class_name).present?
    rescue NameError
      return false
    end
  end
end
