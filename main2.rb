require "net/http"
require "uri"
require "json"

BNK_BASE = "https://public.bitbank.cc"
BTM_BASE = "https://api.bithumb.com"

def es_post(path, body)
  url = "http://#{ENV['ES_URL']}/#{path}"

  STDERR.puts "POST: #{url} with #{body}"

  uri = URI.parse(url)
  header = { 'Content-Type': 'text/json' }
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.request_uri, header)
  request.body = body
  http.request(request)
end

loop do
  krw_jpy = JSON.parse(Net::HTTP.get(URI.parse('http://api.aoikujira.com/kawase/json/jpy'))).fetch('KRW').to_f
  now = Time.now.freeze

  bnk_tickers = { }

  %w(btc_jpy xrp_jpy ltc_btc eth_btc bcc_jpy).each do |pair|
    url = "#{BNK_BASE}/#{pair}/ticker"
    json = Net::HTTP.get(URI.parse(url))
    body = JSON.parse(json)
    bnk_tickers[pair] = body["data"]["sell"]
  end

  bnk_tickers["ltc_jpy"] = bnk_tickers.delete('ltc_btc').to_f * bnk_tickers["btc_jpy"].to_f
  bnk_tickers["eth_jpy"] = bnk_tickers.delete('eth_btc').to_f * bnk_tickers["btc_jpy"].to_f

  btm_tickers = { }

  %w(BTC XRP LTC ETH BCH).each do |currency|
    url = "#{BTM_BASE}/public/ticker/#{currency}"
    json = Net::HTTP.get(URI.parse(url))
    body = JSON.parse(json)
    btm_tickers[currency] = body["data"]["sell_price"].to_f * krw_jpy
  end

  %w(btc_jpy xrp_jpy ltc_jpy eth_jpy bcc_jpy).each_with_index do |pair, i|
    price = btm_tickers.values[i] / bnk_tickers[pair]

    es_post('ticker/deviation', {
      timestamp: now.to_i,
      symbol: btm_tickers.keys[i],
      price: price
    }.to_json)
  end
end
