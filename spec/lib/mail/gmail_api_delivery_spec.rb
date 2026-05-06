require 'rails_helper'

RSpec.describe Mail::GmailApiDelivery do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :google_rest_email, account: account) }
  let(:access_token) { channel.provider_config['access_token'] }
  let(:send_url) { 'https://gmail.googleapis.com/gmail/v1/users/me/messages/send' }

  let(:rendered_mail) do
    Mail.new do
      to      'recipient@example.com'
      from    'agent@example.com'
      subject 'Hello'
      body    'World'
    end
  end

  before do
    refresh_service = instance_double(Google::RefreshOauthTokenService, access_token: access_token)
    allow(Google::RefreshOauthTokenService).to receive(:new).with(channel: channel).and_return(refresh_service)
  end

  describe '#deliver!' do
    it 'posts the base64url encoded MIME body to users.messages.send' do
      stub_request(:post, send_url)
        .to_return(status: 200, body: { id: 'sent-1' }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      described_class.new(channel: channel).deliver!(rendered_mail)

      expect(WebMock).to have_requested(:post, send_url)
        .with(headers: {
                'Authorization' => "Bearer #{access_token}",
                'Content-Type' => 'application/json'
              }) { |req|
          payload = JSON.parse(req.body)
          decoded = Base64.urlsafe_decode64(payload['raw'])
          decoded.include?('Hello') && decoded.include?('recipient@example.com')
        }
    end

    it 'raises OAuth2::Error when the API rejects the send' do
      stub_request(:post, send_url)
        .to_return(status: 403, body: { error: { code: 403, message: 'insufficient scope' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })

      expect { described_class.new(channel: channel).deliver!(rendered_mail) }.to raise_error(OAuth2::Error)
    end
  end
end
