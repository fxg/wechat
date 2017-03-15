<% if defined? ActionController::API -%>
class WechatauthController < ApplicationController
<% else -%>
class WechatauthController < ActionController::Base
<% end -%>
  # For details on the DSL available within this file, see https://github.com/Eric-Guo/wechat#rails-responder-controller-dsl
  wechat_api

  # 公众账号授权页面
  def authorize_page
    wechat_authorize_page('/wx/auth')
  end
end
