local http = require "resty.http"

local plugin = {
  PRIORITY = 1000,
  VERSION = "0.1",
}

-- iterator da configuração
local function iter(config_array)
  if type(config_array) ~= "table" then
    return noop
  end

  return function(config_array, i)
    i = i + 1

    local iter_config = config_array[i]
    if iter_config == nil then -- n + 1
      return nil
    end

    local header_name = iter_config.header_name
    local header_value = iter_config.header_value
    local url = iter_config.url

    if header_name == "" then
      header_name = nil
    end
    if header_value == "" then
      header_value = nil
    end
    if url == "" then
      url = nil
    end

    return i, header_name, header_value, url
  end, config_array, 0
end

-- retorna a url a ser chamada
local function getURL(plugin_conf)

  kong.log.debug("buscando url de customização")
  kong.log.debug(plugin_conf.around[1].header_name)

  for _, header_name, header_value, url in iter(plugin_conf.around) do
    local req_header_value = kong.request.get_header(header_name)

    kong.log.debug("iter config -> header_name: "..header_name.." header_value: "..header_value.." url: "..url)

    if (header_value == req_header_value) then
      return url
    end
  end

  return nil
end

local function make_request(plugin_conf, customizationUrl)
  local scheme, host, port, _ = unpack(http:parse_uri(customizationUrl))

  local client = http.new()
  client:set_timeout(plugin_conf.timeout)
  -- client:set_keepalive(10000)
  client:connect(host, port)
  if scheme == "https" then
      local ok, err = client:ssl_handshake()
      if not ok then
          kong.log.err(err)
          return kong.response.exit(500, { message = "An unexpected error occurred" })
      end
  end

  local res, err = client:request{
    path = customizationUrl,
    method = kong.request.get_method(),
    headers = kong.request.get_headers(),
    body = kong.request.get_raw_body(),
    keepalive_timeout = plugin_conf.timeout,
    ssl_verify = false
  }

  kong.log.debug("request feito")

  if not res then
    kong.log.err(err)
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  return res
end

function plugin:access(plugin_conf)
  
  local url = getURL(plugin_conf)

  if url ~= nil then
    kong.log.debug("redireciona pra fora e pega a resposta e manda pro upstream service")
    -- local response = make_request(plugin_conf, url)
    -- local response_headers = response.headers
    -- local response_body = response:read_body()
    -- kong.log.debug("response body: "..response_body)
    -- kong.log.debug(type(response_body))
    -- return kong.response.exit(response.status, {message = response_body}, response_headers)
    local scheme, host, port, path = unpack(http:parse_uri(url))

    kong.service.set_target(host, port)
    kong.service.request.set_scheme(scheme)
    kong.service.request.set_path(path)

  end

end

return plugin
