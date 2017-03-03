module Wechat
  module ControllerApi
    extend ActiveSupport::Concern

    module ClassMethods
      attr_accessor :wechat_api_client, :wechat_cfg_account, :component_appid, :authorizer_appid, :token, :encrypt_mode, :timeout,
                    :skip_verify_ssl, :encoding_aes_key, :trusted_domain_fullname, :oauth2_cookie_duration
    end

    def wechat
      self.class.wechat # Make sure user can continue access wechat at instance level similar to class level
    end

    def wechat_oauth2(scope = 'snsapi_base', page_url, &block)
      wechat.authorizer_appid = params[:appid]

      wechat.jsapi_ticket = Ticket::PublicJsapiTicket.new(wechat.component_appid, wechat.authorizer_appid)
      wechat.jsapi_ticket.ticket # if wechat.jsapi_ticket.oauth2_state.nil?
      wechat.access_token = Token::PublicAccessToken.new(wechat.component_appid, wechat.authorizer_appid)
      wechat.access_token.token

      oauth2_params = {
        appid: wechat.authorizer_appid,
        redirect_uri: page_url,
        scope: scope,
        response_type: 'code',
        state: wechat.jsapi_ticket.oauth2_state,
        component_appid: wechat.component_appid
      }

      return generate_oauth2_url(oauth2_params) unless block_given?
      wechat_public_oauth2(oauth2_params, &block)
    end

    private

    def wechat_public_oauth2(oauth2_params)
      openid  = cookies.signed_or_encrypted[:we_openid]
      p "openid #{openid}"
      unionid = cookies.signed_or_encrypted[:we_unionid]
      # wechat_public_oauth2增加token缓存
      we_token = cookies.signed_or_encrypted[:we_access_token]
      if openid.present?
        yield openid, { 'openid' => openid, 'unionid' => unionid, 'access_token' => we_token } # wechat_public_oauth2增加token缓存
      elsif params[:code].present? && params[:state] == oauth2_params[:state]
        access_info = wechat.web_access_token(params[:code])
        p access_info['openid']
        cookies.signed_or_encrypted[:we_openid] = { value: access_info['openid'], expires: self.class.oauth2_cookie_duration.from_now }
        cookies.signed_or_encrypted[:we_unionid] = { value: access_info['unionid'], expires: self.class.oauth2_cookie_duration.from_now }
        cookies.signed_or_encrypted[:we_access_token] = { value: access_info['access_token'], expires: self.class.oauth2_cookie_duration.from_now } # wechat_public_oauth2增加token缓存
        yield access_info['openid'], access_info
      else
        redirect_to generate_oauth2_url(oauth2_params)
      end
    end

    def generate_oauth2_url(oauth2_params)
      if oauth2_params[:redirect_uri].blank?
        page_url = (td = self.class.trusted_domain_fullname) ? "#{td}#{request.original_fullpath}" : request.original_url
        safe_query = request.query_parameters.reject { |k, _| %w(code state access_token).include? k }.to_query
        oauth2_params[:redirect_uri] = page_url.sub(request.query_string, safe_query)
      end

      if oauth2_params[:scope] == 'snsapi_login'
        "https://open.weixin.qq.com/connect/qrconnect?#{oauth2_params.to_query}#wechat_redirect"
      else
        "https://open.weixin.qq.com/connect/oauth2/authorize?#{oauth2_params.to_query}#wechat_redirect"
      end
    end
  end
end
