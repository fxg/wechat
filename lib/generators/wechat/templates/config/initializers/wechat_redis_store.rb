module Wechat
  def self.redis
    # You can reuse existing redis connection and remove this method if require
    @redis ||= Redis.new # more options see https://github.com/redis/redis-rb#getting-started
  end
end
