module Mail
  class MicrosoftGraphDelivery
    SEND_URL = 'https://graph.microsoft.com/v1.0/me/sendMail'.freeze

    attr_accessor :settings

    def initialize(values)
      @settings = values || {}
      @channel = @settings[:channel]
    end

    def deliver!(mail)
      encoded = Base64.strict_encode64(mail.encoded)
      token = Microsoft::RefreshOauthTokenService.new(channel: @channel).access_token
      response = HTTParty.post(
        SEND_URL,
        body: encoded,
        headers: {
          'Authorization' => "Bearer #{token}",
          'Content-Type' => 'text/plain'
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
