class MicrosoftGraph::FetchEmailService
  pattr_initialize [:channel!, :interval]

  GRAPH_API = 'https://graph.microsoft.com/v1.0/me'.freeze
  FETCHED_CATEGORY = 'ChatwootFetched'.freeze

  def perform
    return [] if channel.provider_config['refresh_token'].blank?

    list_message_ids.filter_map { |id| fetch_and_mark(id) }
  end

  private

  def access_token
    @access_token ||= Microsoft::RefreshOauthTokenService.new(channel: channel).access_token
  end

  def list_message_ids
    days = (interval || 1).to_i
    since = (Time.zone.today - days).strftime('%Y-%m-%dT00:00:00Z')
    filter = "receivedDateTime ge #{since} and not(categories/any(c:c eq '#{FETCHED_CATEGORY}'))"
    response = http_get("#{GRAPH_API}/mailFolders/inbox/messages",
                        query: { '$filter' => filter, '$select' => 'id', '$top' => 50 })
    (response['value'] || []).map { |m| m['id'] }
  end

  def fetch_and_mark(message_id)
    raw = http_get_raw("#{GRAPH_API}/messages/#{message_id}/$value")
    return nil if raw.blank?

    mail = Mail.read_from_string(raw)
    return nil if channel.inbox.messages.exists?(source_id: mail.message_id)

    mark_fetched(message_id)
    mail
  end

  def mark_fetched(message_id)
    http_patch("#{GRAPH_API}/messages/#{message_id}", body: { categories: [FETCHED_CATEGORY] })
  end

  def http_get(url, query: {})
    response = HTTParty.get(url, query: query, headers: auth_headers)
    handle_json_response!(response)
  end

  def http_get_raw(url)
    response = HTTParty.get(url, headers: auth_headers)
    return response.body if response.success?

    raise OAuth2::Error, fake_oauth_response(response)
  end

  def http_patch(url, body:)
    response = HTTParty.patch(url, body: body.to_json,
                                   headers: auth_headers.merge('Content-Type' => 'application/json'))
    handle_json_response!(response)
  end

  def handle_json_response!(response)
    return response.parsed_response || {} if response.success?

    raise OAuth2::Error, fake_oauth_response(response)
  end

  def fake_oauth_response(response)
    parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
    Struct.new(:parsed, :body) do
      def error=(_); end
    end.new(parsed, response.body.to_s)
  end

  def auth_headers
    { 'Authorization' => "Bearer #{access_token}" }
  end
end
