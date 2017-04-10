require 'optparse'
require 'yaml'
require 'redis'
require 'httpclient'
require 'json'
require 'securerandom'

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

    component_verify_ticket_params = {
      component_appid: @component_appid,
      component_appsecret: @component_appsecret,
      component_verify_ticket: component_verify_ticket
    }

    clnt = HTTPClient.new()
    resp = clnt.post("#{API_BASE}component/api_component_token", JSON.generate(component_verify_ticket_params))
    component_access_token_hash = JSON.parse(resp.body)

    raise "#{component_access_token_hash}" if component_access_token_hash['errcode'].to_i > 0

    redis.multi
    redis.hmset component_access_token_key, "component_access_token", "#{component_access_token_hash['component_access_token']}", "got_token_at", "#{Time.now.to_i}", "expires_in", "#{component_access_token_hash['expires_in']}"
    redis.expire component_access_token_key, component_access_token_hash['expires_in']
    redis.exec
  rescue
    p $!
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

    authorizer_access_token_params = {
      component_appid: component_appid,
      authorizer_appid: authorizer_appid,
      authorizer_refresh_token: authorizer_refresh_token
    }

    clnt = HTTPClient.new()
    resp = clnt.post("#{API_BASE}component/api_authorizer_token?component_access_token=#{component_access_token}", JSON.generate(authorizer_access_token_params))
    authorizer_access_token_hash = JSON.parse(resp.body)

    raise "#{authorizer_access_token_hash}" if authorizer_access_token_hash['errcode'].to_i > 0

    redis.multi
    redis.hmset authorizer_access_token_key, "authorizer_access_token", "#{authorizer_access_token_hash['authorizer_access_token']}", "expires_in", "#{authorizer_access_token_hash['expires_in']}", "authorizer_refresh_token", "#{authorizer_access_token_hash['authorizer_refresh_token']}", "get_token_at", "#{Time.now.to_i}"
    redis.expire authorizer_access_token_key, authorizer_access_token_hash['expires_in']
    redis.exec
  rescue
    p $!
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

    clnt = HTTPClient.new()
    resp = clnt.get("#{API_BASE}ticket/getticket?access_token=#{authorizer_access_token}&type=jsapi")
    jsapi_ticket_key_hash = JSON.parse(resp.body)

    raise "#{jsapi_ticket_key_hash}" if jsapi_ticket_key_hash['errcode'].to_i > 0

    redis.multi
    redis.hmset jsapi_ticket_key, "ticket", "#{jsapi_ticket_key_hash['ticket']}", "oauth2_state", "#{SecureRandom.hex(16)}",  "expires_in", "#{jsapi_ticket_key_hash['expires_in']}", "errcode", "#{jsapi_ticket_key_hash['errcode']}", "errmsg", "#{jsapi_ticket_key_hash['errmsg']}", "get_token_at", "#{Time.now.to_i}"
    redis.expire jsapi_ticket_key, jsapi_ticket_key_hash['expires_in']
    redis.exec
  rescue
    p $!
  end

  private

  def expires?
    return false unless redis.exists(authorizer_access_token_key)
    return true unless redis.exists(pre_auth_code_key)

    got_token_at, expires_in = redis.hmget pre_auth_code_key, "got_token_at", "expires_in"
    true if ((Time.now.to_i - got_token_at) >= (expires_in - 30*60))
  end
end

options = {}
option_parser = OptionParser.new do |opts|
  # 这里是这个命令行工具的帮助信息
  opts.banner = 'here is help messages of the command line tool.'

  options[:env] = 'default'
  opts.on('-e ENV', '--env ENV', 'rails env') do |value|
    # 这个部分就是使用这个Option后执行的代码
    options[:env] = value
  end

  opts.on('-r FILE', '--redis_conf File', 'redis config file') do |value|
    options[:redis_conf] = value
  end

  opts.on('-a FILE', '--apps_conf File', 'wechat component applications secret file') do |value|
    options[:apps_conf] = value
  end
end.parse!

# ruby test.rb -e default --redisconf "/Users/fengxinguo/projects/detai/member/config/redis.yml" -a "/Users/fengxinguo/projects/detai/member/config/wechat_component_apps.yml"

def resovle_config_file(config_file, env)
  if File.exist?(config_file)
    raw_data = YAML.load(File.read(config_file))
    configs = {}
    if env
      # Process multiple accounts when env is given
      raw_data.each do |key, value|
        configs[:default] = value if key == env
      end
    else
      # Treat is as one account when env is omitted
      configs[:default] = raw_data
    end

    configs[:default]
  end
end

redis_configs = resovle_config_file(options[:redis_conf], options[:env])
apps_configs = resovle_config_file(options[:apps_conf], options[:env])

redis_cli = Redis.new(redis_configs)

wechat_keys = redis_cli.keys "wechat_component_verify_ticket_*"
wechat_keys.each do |key|
  # 获取component_appid
  next unless key =~ /wechat_component_verify_ticket_(.*)/
  component_appid = $1
  next if component_appid == ''

  next if apps_configs["#{component_appid}"].nil?

  ComponentAccessToken.new(redis_cli, component_appid, apps_configs["#{component_appid}"]).refresh

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
