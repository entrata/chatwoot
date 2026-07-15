require 'rails_helper'

RSpec.describe Mail::MicrosoftGraphDelivery do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :microsoft_rest_email, account: account) }
  let(:access_token) { channel.provider_config['access_token'] }
  let(:send_url) { 'https://graph.microsoft.com/v1.0/me/sendMail' }

  let(:rendered_mail) do
    Mail.new do
      to      'recipient@example.com'
      from    'agent@example.com'
      subject 'Hello'
      body    'World'
    end
  end

  before do
    refresh_service = instance_double(Microsoft::RefreshOauthTokenService, access_token: access_token)
    allow(Microsoft::RefreshOauthTokenService).to receive(:new).with(channel: channel).and_return(refresh_service)
  end

  describe '#deliver!' do
    it 'posts the base64 encoded MIME body to /me/sendMail with text/plain' do
      stub_request(:post, send_url)
        .to_return(status: 202, body: '', headers: {})

      described_class.new(channel: channel).deliver!(rendered_mail)

      expect(WebMock).to have_requested(:post, send_url)
        .with(headers: {
                'Authorization' => "Bearer #{access_token}",
                'Content-Type' => 'text/plain'
              }) { |req|
          decoded = Base64.decode64(req.body)
          decoded.include?('Hello') && decoded.include?('recipient@example.com')
        }
    end

    it 'raises OAuth2::Error when the API rejects the send' do
      stub_request(:post, send_url)
        .to_return(status: 403, body: { error: { code: 'ErrorAccessDenied', message: 'forbidden' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(channel: channel).deliver!(rendered_mail) }.to raise_error(OAuth2::Error)
    end
  end
end
