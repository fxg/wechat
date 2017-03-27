module ActionController
  module WechatResponder
    # 页面型
    def wechat_api(opts = {})
      include Wechat::ControllerApi
      self.wechat_cfg_account = opts[:account].present? ? opts[:account].to_sym : :default
      self.wechat_api_client = load_controller_wechat(wechat_cfg_account, opts)
    end

    # 消息型
    def wechat_responder(opts = {})
      include Wechat::Responder
      self.wechat_cfg_account = opts[:account].present? ? opts[:account].to_sym : :default
      self.wechat_api_client = load_controller_wechat(wechat_cfg_account, opts)
    end

    def wechat
      self.wechat_api_client ||= load_controller_wechat(wechat_cfg_account)
    end

    private

    def load_controller_wechat(account, opts = {})
      self.token = opts[:token] || Wechat.config(account).token
      self.encrypt_mode = true
      self.timeout = opts[:timeout] || 20
      self.skip_verify_ssl = opts[:skip_verify_ssl]
      self.encoding_aes_key = opts[:encoding_aes_key] || Wechat.config(account).encoding_aes_key
      self.trusted_domain_fullname = opts[:trusted_domain_fullname] || Wechat.config(account).trusted_domain_fullname
      Wechat.config(account).oauth2_cookie_duration ||= 1.hour
      self.oauth2_cookie_duration = opts[:oauth2_cookie_duration] || Wechat.config(account).oauth2_cookie_duration.to_i.seconds

      self.component_appid = opts[:component_appid] || Wechat.config(account).component_appid

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
