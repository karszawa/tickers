require 'bundler'

Bundler.require

require 'dotenv/load'

require 'net/http'
require 'uri'
require 'json'
require 'pry'

BNK_BASE = 'https://public.bitbank.cc'
BTM_BASE = 'https://api.bithumb.com'

CandleStick = Value.new(:timestamp, :symbol, :start_value, :end_value, :high_value, :low_value)

krw_jpy = JSON.parse(Net::HTTP.get(URI.parse('http://api.aoikujira.com/kawase/json/jpy'))).fetch('KRW').to_f
now = Time.now.freeze

# Bitbank
bnk_thread = Thread.new do
  prices = { }

  %w(btc_jpy xrp_jpy ltc_btc eth_btc bcc_jpy).each do |pair|
    url = "#{BNK_BASE}/#{pair}/transactions"
    json = Net::HTTP.get(URI.parse(url))
    body = JSON.parse(json)
    transactions = body['data']['transactions']

    prices[pair] = transactions.select { |tx| now - Time.at(tx['executed_at'] / 1000) < 60 }.map { |tx| tx['price'].to_f }
  end

  if latest_btc_price = prices['btc_jpy'].first
    prices['ltc_jpy'] = prices['ltc_btc'].map { |price| price * latest_btc_price }
    prices['eth_jpy'] = prices['eth_btc'].map { |price| price * latest_btc_price }
  else
    prices['ltc_jpy'] = []
    prices['eth_jpy'] = []
  end

  candles = %w(btc_jpy xrp_jpy ltc_jpy eth_jpy bcc_jpy).map do |pair|
    CandleStick.with(
      timestamp: now,
      symbol: "bnk_#{pair}",
      start_value: prices[pair].last,
      end_value: prices[pair].first,
      high_value: prices[pair].max,
      low_value: prices[pair].min
    )
  end
end

btm_thread = Thread.new do
  prices = { }

  %w(btc xrp ltc eth bch).each do |currency|
    url = "#{BTM_BASE}/public/recent_transactions/#{currency}?count=100"
    json = Net::HTTP.get(URI.parse(url))
    body = JSON.parse(json)
    transactions = body['data']

    prices[currency] = transactions.select { |tx| now - Chronic.parse(tx['transaction_date']) < 60 }.map { |tx| tx['price'].to_f / krw_jpy }
  end

  %w(btc_jpy xrp_jpy ltc_jpy eth_jpy bcc_jpy).map do |pair|
    currency = (pair == 'bcc_jpy' ? 'bch' : pair.split('_').first)

    CandleStick.with(
      timestamp: now,
      symbol: "btm_#{pair}",
      start_value: prices[currency].last,
      end_value: prices[currency].first,
      high_value: prices[currency].max,
      low_value: prices[currency].min
    )
  end
end

puts bnk_candles = bnk_thread.value
puts btm_candles = btm_thread.value

bnk_candles.each do |candle|
   value = (candle.start_value + candle.end_value) / 2
  `curl -XPOST '#{ENV['ES_URL']}:9200/ticker/#{candle.symbol}' -d { "price": #{value} }`
end

btm_candles.each do |candle|
   value = (candle.start_value + candle.end_value) / 2
  `curl -XPOST '#{ENV['ES_URL']}:9200/ticker/#{candle.symbol}' -d { "price": #{value} }`
end
