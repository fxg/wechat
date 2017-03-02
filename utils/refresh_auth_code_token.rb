require 'mechanize'
require 'json'

# 读取微信配置文件：config/wechat.yml
# 读取redis配置文件:config/redis.conf

# headers = {'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.11; rv:41.0) Gecko/20100101 Firefox/41.0'}
agent = Mechanize.new
resp = agent.post('https://zhiyou.smzdm.com/user/login/ajax_check', {:username => 'fxg@mail.com', :password => 'cczdm123', :redirect_url => 'http://www.smzdm.com', :rememberme => 'on', :captcha => ''}, headers)

time = Time.new.strftime("%Y-%m-%d %H:%M:%S")

result = JSON.parse(resp.body)

if result['error_code'] == 0
  p "#{time.to_s}: 登陆成功(#{result['error_code']})"
  agent.request_headers = headers
  checkin_page = agent.get('http://zhiyou.smzdm.com/user/checkin/jsonp_checkin')
  checkin_data = JSON.parse(checkin_page.body)['data']

  if checkin_data
    p '签到成功'
    p "本次签到增加积分:#{checkin_data['add_point']}"
    p "连续签到次数:#{checkin_data['checkin_num']}"
    p "总积分:#{checkin_data['point']}"
  end
else
 p resp.body
end
