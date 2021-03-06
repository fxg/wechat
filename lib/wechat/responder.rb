require 'English'
require 'wechat/signature'

module Wechat
  module Responder
    extend ActiveSupport::Concern
    include Wechat::ControllerApi
    include Cipher

    included do
      # Rails 5 remove before_filter and skip_before_filter
      if respond_to?(:skip_before_action)
        if respond_to?(:verify_authenticity_token)
          skip_before_action :verify_authenticity_token
        else
          # Rails 5 API mode won't define verify_authenticity_token
          # https://github.com/rails/rails/blob/v5.0.0.beta3/actionpack/lib/abstract_controller/callbacks.rb#L66
          # https://github.com/rails/rails/blob/v5.0.0.beta3/activesupport/lib/active_support/callbacks.rb#L640
          skip_before_action :verify_authenticity_token, raise: false
        end

        # before_action :verify_signature, only: [:show, :create]
        before_action :verify_signature, only: [:show, :create, :auth]
      else
        skip_before_filter :verify_authenticity_token
        before_filter :verify_signature, only: [:show, :create, :auth]
      end
    end

    module ClassMethods
      def on(message_type, with: nil, respond: nil, &block)
        raise 'Unknow message type' unless [:text, :image, :voice, :video, :shortvideo, :link, :event, :click, :view, :scan, :batch_job, :location, :label_location, :fallback].include?(message_type)
        config = respond.nil? ? {} : { respond: respond }
        config[:proc] = block if block_given?

        if with.present?
          raise 'Only text, event, click, view, scan and batch_job can having :with parameters' unless [:text, :event, :click, :view, :scan, :batch_job].include?(message_type)
          config[:with] = with
          if message_type == :scan
            if with.is_a?(String)
              self.known_scan_key_lists = with
            else
              raise 'on :scan only support string in parameter with, detail see https://github.com/Eric-Guo/wechat/issues/84'
            end
          end
        else
          raise 'Message type click, view, scan and batch_job must specify :with parameters' if [:click, :view, :scan, :batch_job].include?(message_type)
        end

        case message_type
        when :click
          user_defined_click_responders(with) << config
        when :view
          user_defined_view_responders(with) << config
        when :batch_job
          user_defined_batch_job_responders(with) << config
        when :scan
          user_defined_scan_responders << config
        when :location
          user_defined_location_responders << config
        when :label_location
          user_defined_label_location_responders << config
        else
          user_defined_responders(message_type) << config
        end
        config
      end

      def user_defined_click_responders(with)
        @click_responders ||= {}
        @click_responders[with] ||= []
      end

      def user_defined_view_responders(with)
        @view_responders ||= {}
        @view_responders[with] ||= []
      end

      def user_defined_batch_job_responders(with)
        @batch_job_responders ||= {}
        @batch_job_responders[with] ||= []
      end

      def user_defined_scan_responders
        @scan_responders ||= []
      end

      def user_defined_location_responders
        @location_responders ||= []
      end

      def user_defined_label_location_responders
        @label_location_responders ||= []
      end

      def user_defined_responders(type)
        @responders ||= {}
        @responders[type] ||= []
      end

      def responder_for(message)
        message_type = message[:MsgType].to_sym
        responders = user_defined_responders(message_type)

        case message_type
        when :text
          yield(* match_responders(responders, message[:Content]))
        when :event
          if 'click' == message[:Event] && !user_defined_click_responders(message[:EventKey]).empty?
            yield(* user_defined_click_responders(message[:EventKey]), message[:EventKey])
          elsif 'view' == message[:Event] && !user_defined_view_responders(message[:EventKey]).empty?
            yield(* user_defined_view_responders(message[:EventKey]), message[:EventKey])
          elsif 'click' == message[:Event]
            yield(* match_responders(responders, message[:EventKey]))
          elsif known_scan_key_lists.include?(message[:EventKey]) && %w(scan subscribe scancode_push scancode_waitmsg).freeze.include?(message[:Event])
            yield(* known_scan_with_match_responders(user_defined_scan_responders, message))
          elsif 'batch_job_result' == message[:Event]
            yield(* user_defined_batch_job_responders(message[:BatchJob][:JobType]), message[:BatchJob])
          elsif 'location' == message[:Event]
            yield(* user_defined_location_responders, message)
          else
            yield(* match_responders(responders, message[:Event]))
          end
        when :location
          yield(* user_defined_label_location_responders, message)
        else
          yield(responders.first)
        end
      end

      private

      def match_responders(responders, value)
        matched = responders.each_with_object({}) do |responder, memo|
          condition = responder[:with]

          if condition.nil?
            memo[:general] ||= [responder, value]
            next
          end

          if condition.is_a? Regexp
            memo[:scoped] ||= [responder] + $LAST_MATCH_INFO.captures if value =~ condition
          else
            memo[:scoped] ||= [responder, value] if value == condition
          end
        end
        matched[:scoped] || matched[:general]
      end

      def known_scan_with_match_responders(responders, message)
        matched = responders.each_with_object({}) do |responder, memo|
          if %w(scan subscribe).freeze.include?(message[:Event]) && message[:EventKey] == responder[:with]
            memo[:scaned] ||= [responder, message[:Ticket]]
          elsif %w(scancode_push scancode_waitmsg).freeze.include?(message[:Event]) && message[:EventKey] == responder[:with]
            memo[:scaned] ||= [responder, message[:ScanCodeInfo][:ScanResult], message[:ScanCodeInfo][:ScanType]]
          end
        end
        matched[:scaned]
      end

      def known_scan_key_lists
        @known_scan_key_lists ||= []
      end

      def known_scan_key_lists=(qrscene_value)
        @known_scan_key_lists ||= []
        @known_scan_key_lists << qrscene_value
      end
    end

    def show
      if Rails::VERSION::MAJOR >= 4
        render plain: params[:echostr]
      else
        render text: params[:echostr]
      end
    end

    def create
      # 设置本次会话的授权应用appid：authorizer_appid
      wechat.authorizer_appid = params[:authorizer_appid]
      # 获取或刷新对应authorizer_appid的token

      request_msg = Wechat::Message.from_hash(post_xml)
      response_msg = run_responder(request_msg)

      if response_msg.respond_to? :to_xml
        if Rails::VERSION::MAJOR >= 4
          render plain: process_response(response_msg)
        else
          render text: process_response(response_msg)
        end
      else
        head :ok, content_type: 'text/html'
      end

      # response_msg.save_session if response_msg.is_a?(Wechat::Message)

      ActiveSupport::Notifications.instrument 'wechat.responder.after_create', request: request_msg, response: response_msg
    end

    def auth
      info_type = post_xml[:InfoType].to_sym
      auth_header = "wechat_#{info_type}_"
      case info_type
      when :component_verify_ticket
        Wechat.redis.hmset("#{auth_header}#{post_xml['AppId']}", "AppId", "#{post_xml['AppId']}", "ComponentVerifyTicket", "#{post_xml['ComponentVerifyTicket']}", "InfoType", "#{post_xml['InfoType']}", "CreateTime", "#{post_xml['CreateTime']}")
      when :unauthorized
        Wechat.redis.hmset("#{auth_header}#{post_xml['AppId']}_#{post_xml['AuthorizerAppid']}", "CreateTime", "#{post_xml['CreateTime']}")
        Wechat.redis.del("wechat_authorized_#{post_xml['AppId']}_#{post_xml['AuthorizerAppid']}")
        Wechat.redis.del("wechat_authorization_info_#{post_xml['AppId']}_#{post_xml['AuthorizerAppid']}")
        Wechat.redis.del("wechat_authorizer_access_token_#{post_xml['AppId']}_#{post_xml['AuthorizerAppid']}")
        Wechat.redis.del("wechat_jsapi_ticket_key_#{post_xml['AppId']}_#{post_xml['AuthorizerAppid']}")
      when :authorized, :updateauthorized
        Wechat.redis.hmset("#{auth_header}#{post_xml['AppId']}_#{post_xml['AuthorizerAppid']}", "CreateTime", "#{post_xml['CreateTime']}", "AuthorizationCode", "#{post_xml['AuthorizationCode']}", "AuthorizationCodeExpiredTime", "#{post_xml['AuthorizationCodeExpiredTime']}")
      end
    ensure
      if Rails::VERSION::MAJOR >= 4
        render plain: "success"
      else
        render text: "success"
      end
    end

    def auth_callback
      # 获取授权信息并展示，然后跳转到其他页面.
      component_appid, authorizer_appid = authorizer_info

      if params[:component_redirect_uri].nil?
        render plain: "authorize ok!"
      else
        redirect_to "#{params[:component_redirect_uri]}&component_appid=#{component_appid}&authorizer_appid=#{authorizer_appid}"
      end
    end

    private

    API_BASE = 'https://api.weixin.qq.com/cgi-bin/'.freeze

    def authorizer_info
      url_params = {
        component_access_token: Token::AccessToken.new(wechat.component_appid).component_access_token
      }

      # 获取授权公众号的信息及相关token
      resp = wechat.client.post("component/api_query_auth", JSON.generate(component_appid: wechat.component_appid, authorization_code: params[:auth_code]), params: url_params, base: API_BASE)

      authorization_info_hash = resp['authorization_info']

      component_appid = wechat.component_appid
      authorizer_appid = authorization_info_hash['authorizer_appid']
      authorizer_access_token = authorization_info_hash['authorizer_access_token']

      wechat_authorizer_access_token_key = "wechat_authorizer_access_token_#{component_appid}_#{authorizer_appid}"
      Wechat.redis.multi
      Wechat.redis.set "wechat_authorization_info_#{component_appid}_#{authorizer_appid}", authorization_info_hash.to_json
      Wechat.redis.hmset wechat_authorizer_access_token_key, "authorizer_access_token", "#{authorizer_access_token}", "expires_in", "#{authorization_info_hash['expires_in']}", "authorizer_refresh_token", "#{authorization_info_hash['authorizer_refresh_token']}", "get_token_at", "#{Time.now.to_i}"
      # Wechat.redis.expire wechat_authorizer_access_token_key, authorization_info_hash['expires_in']
      Wechat.redis.exec

      # 获取授权公众号的ticket
      resp = wechat.client.get("ticket/getticket?access_token=#{authorizer_access_token}&type=jsapi", base: API_BASE)

      jsapi_ticket_key = "wechat_jsapi_ticket_key_#{component_appid}_#{authorizer_appid}"
      jsapi_ticket_key_hash = resp

      Wechat.redis.multi
      Wechat.redis.hmset jsapi_ticket_key, "ticket", "#{jsapi_ticket_key_hash['ticket']}", "oauth2_state", "#{SecureRandom.hex(16)}",  "expires_in", "#{jsapi_ticket_key_hash['expires_in']}", "errcode", "#{jsapi_ticket_key_hash['errcode']}", "errmsg", "#{jsapi_ticket_key_hash['errmsg']}", "get_token_at", "#{Time.now.to_i}"
      Wechat.redis.expire jsapi_ticket_key, jsapi_ticket_key_hash['expires_in']
      Wechat.redis.exec

      [ component_appid, authorizer_appid ]
    end

    def verify_signature
      if self.class.encrypt_mode
        signature = params[:signature] || params[:msg_signature]
      else
        signature = params[:signature]
      end

      render plain: 'Forbidden', status: 403 if signature != Signature.hexdigest(self.class.token,
                                                                                 params[:timestamp],
                                                                                 params[:nonce],
                                                                                 nil)
    end

    def post_xml
      data = request_content
      if self.class.encrypt_mode && request_encrypt_content.present?
        content, @app_id = unpack(decrypt(Base64.decode64(request_encrypt_content), self.class.encoding_aes_key))
        data = Hash.from_xml(content)
      end

      data_hash = data.fetch('xml', {})

      if Rails::VERSION::MAJOR >= 5
        data_hash = data_hash.to_unsafe_hash if data_hash.instance_of?(ActionController::Parameters)
        HashWithIndifferentAccess.new(data_hash).tap do |msg|
          msg[:Event].downcase! if msg[:Event]
        end
      else
        HashWithIndifferentAccess.new_from_hash_copying_default(data_hash).tap do |msg|
          msg[:Event].downcase! if msg[:Event]
        end
      end
    end

    def run_responder(request)
      self.class.responder_for(request) do |responder, *args|
        responder ||= self.class.user_defined_responders(:fallback).first
        next if responder.nil?
        case
        when responder[:respond]
          request.reply.text responder[:respond]
        when responder[:proc]
          define_singleton_method :process, responder[:proc]
          number_of_block_parameter = responder[:proc].arity
          send(:process, *args.unshift(request).take(number_of_block_parameter))
        else
          next
        end
      end
    end

    def process_response(response)
      msg = response[:MsgType] == 'success' ? 'success' : response.to_xml

      if self.class.encrypt_mode
        encrypt = Base64.strict_encode64(encrypt(pack(msg, @app_id), self.class.encoding_aes_key))
        msg = gen_msg(encrypt, params[:timestamp], params[:nonce])
      end
      msg
    end

    def gen_msg(encrypt, timestamp, nonce)
      msg_sign = Signature.hexdigest(self.class.token, timestamp, nonce, encrypt)

      { Encrypt: encrypt,
        MsgSignature: msg_sign,
        TimeStamp: timestamp,
        Nonce: nonce
      }.to_xml(root: 'xml', children: 'item', skip_instruct: true, skip_types: true)
    end

    def request_encrypt_content
      request_content['xml']['Encrypt']
    end

    def request_content
      params[:xml].nil? ? Hash.from_xml(request.raw_post) : { 'xml' => params[:xml] }
    end
  end
end
