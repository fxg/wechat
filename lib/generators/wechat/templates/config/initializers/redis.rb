require 'redis'
require 'redis/objects'
require 'connection_pool'

REDIS_CONFIG = YAML.load( File.open( Rails.root.join("config/redis.yml") ) ).symbolize_keys
dflt = REDIS_CONFIG[:default].symbolize_keys
cnfg = dflt.merge(REDIS_CONFIG[Rails.env.to_sym].symbolize_keys) if REDIS_CONFIG[Rails.env.to_sym]

$redis = Redis.new(cnfg)
Redis::Objects.redis = ConnectionPool.new(size: 5, timeout: 5) { $redis }

# To clear out the db before each test
$redis.flushdb if Rails.env == "test"