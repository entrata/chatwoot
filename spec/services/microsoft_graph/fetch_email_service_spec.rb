require 'rails_helper'

RSpec.describe MicrosoftGraph::FetchEmailService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :microsoft_rest_email, account: account) }
  let(:access_token) { channel.provider_config['access_token'] }
  let(:eml_content) { Rails.root.join('spec/fixtures/files/only_text.eml').read }
  let(:graph_message_id) { 'AAMkAG-message-id' }

  let(:list_url) { 'https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages' }
  let(:value_url) { "https://graph.microsoft.com/v1.0/me/messages/#{graph_message_id}/$value" }
  let(:patch_url) { "https://graph.microsoft.com/v1.0/me/messages/#{graph_message_id}" }

  before do
    refresh_service = instance_double(Microsoft::RefreshOauthTokenService, access_token: access_token)
    allow(Microsoft::RefreshOauthTokenService).to receive(:new).with(channel: channel).and_return(refresh_service)
  end

  describe '#perform' do
    context 'when refresh_token is missing from provider_config' do
      it 'returns an empty array without calling the API' do
        channel.update!(provider_config: channel.provider_config.merge('refresh_token' => nil))

        expect(described_class.new(channel: channel, interval: 1).perform).to eq([])
      end
    end

    context 'when new mail is available' do
      before do
        stub_request(:get, list_url)
          .with(query: hash_including('$select' => 'id'))
          .to_return(status: 200, body: { value: [{ id: graph_message_id }] }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        stub_request(:get, value_url)
          .with(headers: { 'Authorization' => "Bearer #{access_token}" })
          .to_return(status: 200, body: eml_content,
                     headers: { 'Content-Type' => 'text/plain' })

        stub_request(:patch, patch_url)
          .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns parsed Mail objects for new messages' do
        result = described_class.new(channel: channel, interval: 1).perform

        expect(result.length).to eq(1)
        expect(result.first.message_id).to eq('6215e5ca3e3b2_10bc6197e4224d1@tejaswinis-MacBook-Pro.local.mail')
      end

      it 'marks the fetched message with the ChatwootFetched category' do
        described_class.new(channel: channel, interval: 1).perform

        expect(WebMock).to have_requested(:patch, patch_url)
          .with(body: { categories: ['ChatwootFetched'] }.to_json)
      end

      it 'filters by receivedDateTime and excludes already-fetched category' do
        described_class.new(channel: channel, interval: 1).perform

        expect(WebMock).to have_requested(:get, list_url)
          .with(query: hash_including('$filter' => /receivedDateTime ge .+ChatwootFetched/m))
      end

      it 'skips messages already present in the inbox' do
        create(:message,
               source_id: '6215e5ca3e3b2_10bc6197e4224d1@tejaswinis-MacBook-Pro.local.mail',
               inbox: channel.inbox, account: account)

        result = described_class.new(channel: channel, interval: 1).perform

        expect(result).to eq([])
        expect(WebMock).not_to have_requested(:patch, patch_url)
      end
    end

    context 'when the API returns an auth error' do
      before do
        stub_request(:get, list_url)
          .to_return(status: 403, body: { error: { code: 'ErrorAccessDenied', message: 'forbidden' } }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'raises OAuth2::Error so the job marks the channel for reauthorization' do
        expect { described_class.new(channel: channel, interval: 1).perform }.to raise_error(OAuth2::Error)
      end
    end
  end
end
