config = require './config.json'
xmpp = require 'node-xmpp'
util = require 'util'
http = require 'http'
ltx = require 'ltx'
async = require 'async'

admin_jid = config.admin_jid

http_get = (url, cb) ->
	http.get url, (res) ->
		buffer = ""
		res.on 'data', (chunk) ->
			buffer += chunk
		res.on 'end', ->
			cb buffer 

client = new xmpp.Client
	host: config.host
	jid: config.jid
	password: config.password

send_message = (to, msg) ->
	client.send new xmpp.Element('message',
		to: to
		type: 'chat'
	).c('body').t(msg)

help_str = '''使用帮助:
[美元汇率] /usd 1000
[英汉汉英词典] /dict robot
[股票信息] /stock 600000'''

handle_operation = (args) ->
	if m = args.match /memadd (.+)/
		console.log 'memadd', m[1]
		client.send new xmpp.Element 'presence',
			type: 'subscribe',
			to: m[1]
	else if m = args.match /memdel (.+)/
		console.log 'memdel', m[1]
		client.send new xmpp.Element('iq', type: 'set').c(
			'query', xmlns: 'jabber:iq:roster').c(
			'item', jid: m[1], subscription: 'remove')
	else if m = args.match /memls/
		client.send new xmpp.Element('iq',
				type: 'get'
				id: 'roster_0'
			).c 'query'
				xmlns: 'jabber:iq:roster'
	else 
		console.log 'unknown operation'

handle_usd = (from, args) ->
	if args.match /^[0-9\.]+$/
		urls = [
			["CNY", "http://api.liqwei.com/currency/?exchange=CNY|USD&count="],
			["USD", "http://api.liqwei.com/currency/?exchange=USD|CNY&count="]
		]
		async.reduce urls, [], ((resp, item, cb) ->
			http_get item[1] + args, (data) ->
				resp.push "#{item[0]} #{args} = #{if item[0] == 'CNY' then 'USD' else 'CNY'} #{data}"
				cb null, resp
			), (err, resp) ->
				send_message from, resp.join '\r\n'
	else
		send_message from, '请输入数字'

handle_dict = (from, args) ->
	url = "http://fanyi.youdao.com/openapi.do?keyfrom=localhost2&key=1311886079&type=data&doctype=json&version=1.1&q="
	http_get (url + encodeURIComponent(args)), (buffer) ->
		data = JSON.parse buffer

		if data.errorCode == 0
			resp = [
				"【#{args}】"
			]
			if data.basic
				resp.push "=== 基本 ==="
				resp.push "[#{data.basic.phonetic}]" if data.basic.phonetic
				for exp in data.basic.explains
					resp.push exp
				resp.push '=== 更多 ==='

			if data.web
				for item in data.web
					resp.push "#{item.key} #{item.value}"

			send_message from, resp.join '\r\n'
		else
			send_message from, '出错了, ' + 
				{
					20: '要翻译的文本过长',
					30: '无法进行有效的翻译',
					40: '不支持的语言类型',
					50: '无效的key'
				}[data.errorCode]

handle_stock = (from, args) ->
	try
		if m = args.match /([0-9]+)/
			code = m[1]
			url = "http://www.google.com/ig/api?stock=#{code}"
			http_get url, (buffer) ->
				data = ltx.parse(buffer).getChild('finance')
				response = [
					"名称: #{data.getChild('company').attrs.data}",
					"当前: CNY#{data.getChild('last').attrs.data}",
					"开盘: CNY#{data.getChild('low').attrs.data}",
					"最高: CNY#{data.getChild('high').attrs.data}",
					"最低: CNY#{data.getChild('low').attrs.data}",
					"涨跌: #{data.getChild('change').attrs.data}",
					"成交: #{data.getChild('volume').attrs.data}"
				]
				send_message from, response.join "\r\n"
	catch error
		console.log 'handle_stock_error', error
		send_message from, "不好意思出错了!"

client.on 'online', ->
	console.log 'online'
	client.send new xmpp.Element 'presence'

client.on 'error', (e) ->
	console.log 'error', e

client.on 'stanza', (stanza) ->
	if stanza.attrs.type == 'error'
		console.log 'error', stanza
	else if stanza.name == 'message' and stanza.type == 'chat'
		if body = stanza.getChild 'body'
			msg = body.getText().trim()
			if msg.substr(0, 7) == '/admin ' and stanza.attrs.from.indexOf admin_jid == 0
				handle_operation msg.substr 7
			else if msg.substr(0, 5) == '/help'
				send_message stanza.attrs.from, help_str
			else if msg.substr(0, 7) == '/stock '
				handle_stock stanza.attrs.from, msg.substr 7
			else if msg.substr(0, 6) == '/dict '
				handle_dict stanza.attrs.from, msg.substr 6
			else if msg.substr(0, 5) == '/usd '
				handle_usd stanza.attrs.from, msg.substr 5
			else
				stanza.attrs.to = stanza.attrs.from
				delete stanza.attrs.from
				client.send stanza
	else if stanza.name == 'iq'
		if stanza.attrs.id = 'roster_0' and stanza.attrs.type = 'result'
			for _stanza in stanza.children
				if _stanza.name == 'query'
					roster = for __stanza in _stanza.children
						"#{__stanza.attrs.jid}, #{__stanza.attrs.subscription}"
					console.log 'roster', roster
					send_message admin_jid, roster.join '\r\n'
	else if stanza.name == 'presence'
		if stanza.attrs.type == 'subscribe'
			console.log 'subscribe', stanza.attrs.from
			send_message admin_jid, "'#{stanza.attrs.from}'申请加入, 回复'/admin memadd #{stanza.attrs.from}'添加此人！"
		else if stanza.attrs.type == 'unavailable'
			console.log 'unavailable', stanza.attrs.from
		else
			console.log stanza, stanza.attrs.from
	else
		console.log '?', stanza


