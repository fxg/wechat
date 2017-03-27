require 'mechanize'
require 'json'
require 'yaml'
require 'redis'
require 'securerandom'
require_relative 'http_client'

class ComponentAccessToken
  attr_reader :redis, :component_appid, :component_appsecret, :component_access_token_key, :component_verify_ticket_key
  API_BASE = 'https://api.weixin.qq.com/cgi-bin/'.freeze

  def initialize(redis, component_appid, component_appsecret)
    @redis = redis
    @component_appid = component_appid
    @component_appsecret = component_appsecret
    @component_access_token_key = "wechat_component_access_token_#{component_appid}"
    @component_verify_ticket_key = "wechat_component_verify_ticket_#{component_appid}"
  end

  def refresh
    # exit unless expires?
    # 获取component_verify_ticket
    component_verify_ticket = redis.hget component_verify_ticket_key, "ComponentVerifyTicket"

    client = HttpClient.new(API_BASE, 20, true)

    component_verify_ticket_params = {
      component_appid: component_appid,
      component_appsecret: component_appsecret,
      component_verify_ticket: component_verify_ticket
    }
    component_access_token_hash = client.post('component/api_component_token', JSON.generate(component_verify_ticket_params))

    redis.hmset component_access_token_key, "component_access_token", "#{component_access_token_hash['component_access_token']}", "got_token_at", "#{Time.now.to_i}", "expires_in", "#{component_access_token_hash['expires_in']}"
  end

  private

  def expires?
    return false unless redis.exists(component_verify_ticket_key)
    return true unless redis.exists(component_access_token_key)

    got_token_at, expires_in = redis.hmget component_access_token_key, "got_token_at", "expires_in"
    true if ((Time.now.to_i - got_token_at.to_i) >= (expires_in.to_i - 30*60))
  end
end

class AuthorizerAccessToken
  attr_reader :redis, :component_appid, :authorizer_appid, :component_access_token_key, :authorizer_access_token_key
  API_BASE = 'https://api.weixin.qq.com/cgi-bin/'.freeze

  def initialize(redis, component_appid, authorizer_appid)
    @redis = redis
    @component_appid = component_appid
    @authorizer_appid = authorizer_appid
    @authorizer_access_token_key = "wechat_authorizer_access_token_#{component_appid}_#{authorizer_appid}"
    @component_access_token_key = "wechat_component_access_token_#{component_appid}"
  end

  def refresh
    # exit unless expires?
    component_access_token = redis.hget component_access_token_key, "component_access_token"
    authorizer_refresh_token = redis.hget authorizer_access_token_key, "authorizer_refresh_token"

    client = HttpClient.new(API_BASE, 20, true)
    authorizer_access_token_params = {
      component_appid: component_appid,
      authorizer_appid: authorizer_appid,
      authorizer_refresh_token: authorizer_refresh_token
    }
    authorizer_access_token_hash = client.post("component/api_authorizer_token?component_access_token=#{component_access_token}", JSON.generate(authorizer_access_token_params))

    redis.multi
    redis.hmset authorizer_access_token_key, "authorizer_access_token", "#{authorizer_access_token_hash['authorizer_access_token']}", "expires_in", "#{authorizer_access_token_hash['expires_in']}", "authorizer_refresh_token", "#{authorizer_access_token_hash['authorizer_refresh_token']}", "get_token_at", "#{Time.now.to_i}"
    redis.expire authorizer_access_token_key, authorizer_access_token_hash['expires_in']
    redis.exec
  end

  private

  def expires?
    return false unless redis.exists(component_access_token_key)

    got_token_at, expires_in = redis.hmget pre_auth_code_key, "got_token_at", "expires_in"
    true if ((Time.now.to_i - got_token_at) >= (expires_in - 10*60))
  end
end

class JsapiTicket
  attr_reader :redis, :authorizer_access_token_key, :authorizer_appid, :jsapi_ticket_key
  API_BASE = 'https://api.weixin.qq.com/cgi-bin/'.freeze

  def initialize(redis, component_appid, authorizer_appid)
    @redis = redis
    @jsapi_ticket_key = "wechat_jsapi_ticket_key_#{component_appid}_#{authorizer_appid}"
    @authorizer_access_token_key = "wechat_authorizer_access_token_#{component_appid}_#{authorizer_appid}"
  end

  def refresh
    # exit unless expires?
    authorizer_access_token = redis.hget authorizer_access_token_key, "authorizer_access_token"

    client = HttpClient.new(API_BASE, 20, true)
    jsapi_ticket_key_hash = client.get("ticket/getticket?access_token=#{authorizer_access_token}&type=jsapi")

    redis.multi
    redis.hmset jsapi_ticket_key, "ticket", "#{jsapi_ticket_key_hash['ticket']}", "oauth2_state", "#{SecureRandom.hex(16)}",  "expires_in", "#{jsapi_ticket_key_hash['expires_in']}", "errcode", "#{jsapi_ticket_key_hash['errcode']}", "errmsg", "#{jsapi_ticket_key_hash['errmsg']}", "get_token_at", "#{Time.now.to_i}"
    redis.expire jsapi_ticket_key, jsapi_ticket_key_hash['expires_in']
    redis.exec
  end

  private

  def expires?
    return false unless redis.exists(authorizer_access_token_key)
    return true unless redis.exists(pre_auth_code_key)

    got_token_at, expires_in = redis.hmget pre_auth_code_key, "got_token_at", "expires_in"
    true if ((Time.now.to_i - got_token_at) >= (expires_in - 30*60))
  end
end

def resovle_config_file(config_file, env)
  if File.exist?(config_file)
    raw_data = YAML.load(File.read(config_file))
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

app_config = {"component_appid" => "component_appsecret"}

# 读取redis配置文件:config/redis.conf
config_file = ARGV[0] # 文件全路径
env = ARGV[1] # 模式名
configs = resovle_config_file(config_file, env)
config_hash = configs[env.to_sym]

redis_cli = Redis.new(:host => config_hash['host'], :port => config_hash['port'], :db => config_hash['db'] || 0)

wechat_keys = redis_cli.keys "wechat_component_verify_ticket_*"
wechat_keys.each do |key|
  # 获取component_appid
  next unless key =~ /wechat_component_verify_ticket_(.*)/
  component_appid = $1
  next if component_appid == ''

  next if app_config["#{component_appid}"].nil?

  ComponentAccessToken.new(redis_cli, component_appid, app_config["#{component_appid}"]).refresh

  # 刷新auth_access_token,refresh_toekn
  auth_app_keys = redis_cli.keys "wechat_authorization_info_#{component_appid}_*"
  auth_app_keys.each do |auth_app_key|
    # 获取授权方的appid
    next unless auth_app_key =~ /wechat_authorization_info_#{component_appid}_(.*)/
    authorizer_appid = $1
    next if authorizer_appid == ''

    AuthorizerAccessToken.new(redis_cli, component_appid, authorizer_appid).refresh
    JsapiTicket.new(redis_cli, component_appid, authorizer_appid).refresh
  end
end
