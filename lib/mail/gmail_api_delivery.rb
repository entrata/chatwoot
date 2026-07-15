module Mail
  class GmailApiDelivery
    SEND_URL = 'https://gmail.googleapis.com/gmail/v1/users/me/messages/send'.freeze

    attr_accessor :settings

    def initialize(values)
      @settings = values || {}
      @channel = @settings[:channel]
    end

    def deliver!(mail)
      raw = Base64.urlsafe_encode64(mail.encoded)
      token = Google::RefreshOauthTokenService.new(channel: @channel).access_token
      response = HTTParty.post(
        SEND_URL,
        body: { raw: raw }.to_json,
        headers: {
          'Authorization' => "Bearer #{token}",
          'Content-Type' => 'application/json'
        }
      )

      raise OAuth2::Error, fake_oauth_response(response) unless response.success?

      mail
    end

    private

    def fake_oauth_response(response)
      parsed = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
      Struct.new(:parsed, :body) do
        def error=(_); end
      end.new(parsed, response.body.to_s)
    end
  end
end
