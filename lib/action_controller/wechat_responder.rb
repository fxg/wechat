module ActionController
  module WechatResponder
    # 页面型
    def wechat_api(opts = {})
      include Wechat::ControllerApi
      account = opts.delete(:account)
      self.wechat_cfg_account = account ? account.to_sym : :default
      self.wechat_api_client = load_controller_wechat(wechat_cfg_account, opts)
    end

    # 消息型
    def wechat_responder(opts = {})
      include Wechat::Responder
      account = opts.delete(:account)
      self.wechat_cfg_account = account ? account.to_sym : :default
      self.wechat_api_client = load_controller_wechat(wechat_cfg_account, opts)
    end

    def wechat(account = nil)
      if account && account != wechat_cfg_account
        Wechat.api(account)
      else
        self.wechat_api_client ||= load_controller_wechat(wechat_cfg_account)
      end
    end

    private

    def load_controller_wechat(account, opts = {})
      cfg = Wechat.config(account)
      self.token = opts[:token] || cfg.token
      self.encrypt_mode = true
      self.timeout = opts[:timeout] || 20
      if opts.key?(:skip_verify_ssl)
        self.skip_verify_ssl = opts[:skip_verify_ssl]
      else
        self.skip_verify_ssl = cfg.skip_verify_ssl
      end
      self.encoding_aes_key = opts[:encoding_aes_key] || cfg.encoding_aes_key
      self.trusted_domain_fullname = opts[:trusted_domain_fullname] || cfg.trusted_domain_fullname
      cfg.oauth2_cookie_duration ||= 1.hour
      self.oauth2_cookie_duration = opts[:oauth2_cookie_duration] || cfg.oauth2_cookie_duration.to_i.seconds

      self.component_appid = opts[:component_appid] || cfg.component_appid

      return self.wechat_api_client = Wechat.api if account == :default && opts.empty?

      Wechat::Api.new(component_appid, timeout, skip_verify_ssl)
    end
  end

  if defined? Base
    class << Base
      include WechatResponder
    end
  end

  if defined? API
    class << API
      include WechatResponder
    end
  end
end
