require 'mechanize'
require 'json'
require 'yaml'
require 'redis'

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

app_config = {"wxe896c42595e407f0" => "0d9eb3bedb6e83e6250ee9991d75194e"}

# 读取redis配置文件:config/redis.conf
config_file = '/apps/test/weixin/wechattest/config/redis.yml'
env = 'default'
configs = resovle_config_file(config_file, env)
config_hash = configs[env.to_sym]

redis_cli = Redis.new(:host => config_hash['host'], :port => config_hash['port'], :db => 0)
agent = Mechanize.new

wechat_keys = redis_cli.keys "wechat_component_verify_ticket_*"
wechat_keys.each do |key|
  # 获取component_appid
  next unless key =~ /wechat_component_verify_ticket_(.*)/
  component_appid = $1
  next if component_appid == ''

  # component_access_token_hash = JSON.parse(redis_cli.get("component_access_token_#{component_appid}"))
  # component_access_token = component_access_token_hash['component_access_token']
  # got_token_at = component_access_token_hash['got_token_at'].to_i || 0
  # token_expires_in= component_access_token_hash['expires_in'].to_i || 0
  #
  # # 如果快过期，重新刷新component_access_token
  # if ((Time.now.to_i - got_token_at) >= (token_expires_in - 30*60))
    wechat_component_verify_ticket = redis_cli.get key
    wechat_component_verify_ticket_hash = JSON.parse(wechat_component_verify_ticket)
    component_appid = wechat_component_verify_ticket_hash['AppId']
    component_appsecret = app_config["#{component_appid}"]
    wechat_component_verify_ticket_value = wechat_component_verify_ticket_hash['ComponentVerifyTicket']

    # 重新刷新component_access_token
    post_data = "{\"component_appid\" : \"#{component_appid}\", \"component_appsecret\" : \"#{component_appsecret}\", \"component_verify_ticket\" : \"#{wechat_component_verify_ticket_value}\"}"
    resp = agent.post('https://api.weixin.qq.com/cgi-bin/component/api_component_token', post_data)
    component_access_token_hash = JSON.parse(resp.body)
    component_access_token = component_access_token_hash['component_access_token']
    component_access_token_hash['got_token_at'] = Time.now.to_i
    redis_cli.set "component_access_token_#{component_appid}", component_access_token_hash.to_json
  # end

  # pre_auth_code_hash = JSON.parse(redis_cli.get("pre_auth_code_#{component_appid}"))
  # got_code_at = pre_auth_code_hash['got_code_at'].to_i || 0
  # code_expires_in = pre_auth_code_hash['expires_in'].to_i || 0
  # if ((Time.now.to_i - got_code_at) >= (code_expires_in - 10*60))
    # 获取预授权码pre_auth_code
    post_data = "{\"component_appid\" : \"#{component_appid}\"}"
    resp = agent.post("https://api.weixin.qq.com/cgi-bin/component/api_create_preauthcode?component_access_token=#{component_access_token}", post_data)
    pre_auth_code_hash = JSON.parse(resp.body)
    pre_auth_code_hash['got_code_at'] = Time.now.to_i
    redis_cli.set "pre_auth_code_#{component_appid}", pre_auth_code_hash.to_json
  # end

  # 刷新auth_access_token,refresh_toekn
  auth_app_keys = redis_cli.keys "authorization_info_#{component_appid}_*"
  auth_app_keys.each do |auth_app_key|
    # 获取授权方的appid
    next unless auth_app_key =~ /authorization_info_#{component_appid}_(.*)/
    auth_appid = $1
    next if auth_appid == ''

    authorizer_info_hash = JSON.parse(redis_cli.get(auth_app_key))
    authorizer_refresh_token =  authorizer_info_hash['authorizer_refresh_token']

    post_data = "{\"component_appid\" : \"#{component_appid}\", \"authorizer_appid\" : \"#{auth_appid}\", \"authorizer_refresh_token\" : \"#{authorizer_refresh_token}\"}"
    p post_data
    p component_access_token
    resp = agent.post("https://api.weixin.qq.com/cgi-bin/component/api_authorizer_token?component_access_token=#{component_access_token}", post_data)
    p JSON.parse(resp.body)
    authorizer_token_hash = JSON.parse(resp.body)
    authorizer_token_hash['got_token_at'] = Time.now.to_i
    redis_cli.set "authorizer_token_#{component_appid}_#{auth_appid}", authorizer_token_hash.to_json
  end
end
