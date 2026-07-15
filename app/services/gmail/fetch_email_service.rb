class Gmail::FetchEmailService
  pattr_initialize [:channel!, :interval]

  GMAIL_API = 'https://gmail.googleapis.com/gmail/v1/users/me'.freeze
  FETCHED_LABEL = 'CHATWOOT_FETCHED'.freeze

  def perform
    return [] if channel.provider_config['refresh_token'].blank?

    label_id = ensure_fetched_label
    list_message_ids.filter_map { |id| fetch_and_mark(id, label_id) }
  end

  private

  def access_token
    @access_token ||= Google::RefreshOauthTokenService.new(channel: channel).access_token
  end

  def list_message_ids
    days = (interval || 1).to_i
    q = "newer_than:#{days}d in:inbox -label:#{FETCHED_LABEL}"
    response = http_get("#{GMAIL_API}/messages", query: { q: q })
    (response['messages'] || []).map { |m| m['id'] }
  end

  def fetch_and_mark(message_id, label_id)
    response = http_get("#{GMAIL_API}/messages/#{message_id}", query: { format: 'raw' })
    raw_b64 = response['raw']
    return nil if raw_b64.blank?

    mail = Mail.read_from_string(Base64.urlsafe_decode64(raw_b64))
    return nil if channel.inbox.messages.exists?(source_id: mail.message_id)

    add_label(message_id, label_id)
    mail
  end

  def ensure_fetched_label
    labels = http_get("#{GMAIL_API}/labels")['labels'] || []
    existing = labels.find { |l| l['name'] == FETCHED_LABEL }
    return existing['id'] if existing

    response = http_post("#{GMAIL_API}/labels",
                         body: { name: FETCHED_LABEL, labelListVisibility: 'labelHide', messageListVisibility: 'hide' })
    response['id']
  end

  def add_label(message_id, label_id)
    http_post("#{GMAIL_API}/messages/#{message_id}/modify", body: { addLabelIds: [label_id] })
  end

  def http_get(url, query: {})
    response = HTTParty.get(url, query: query, headers: auth_headers)
    handle_response!(response)
  end

  def http_post(url, body:)
    response = HTTParty.post(url, body: body.to_json, headers: auth_headers.merge('Content-Type' => 'application/json'))
    handle_response!(response)
  end

  def handle_response!(response)
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
