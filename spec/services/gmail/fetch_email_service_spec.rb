require 'rails_helper'

RSpec.describe Gmail::FetchEmailService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :google_rest_email, account: account) }
  let(:access_token) { channel.provider_config['access_token'] }
  let(:eml_content) { Rails.root.join('spec/fixtures/files/only_text.eml').read }
  let(:gmail_message_id) { 'gmail-msg-1' }
  let(:label_id) { 'Label_42' }

  let(:list_url) { 'https://gmail.googleapis.com/gmail/v1/users/me/messages' }
  let(:get_url) { "https://gmail.googleapis.com/gmail/v1/users/me/messages/#{gmail_message_id}" }
  let(:labels_url) { 'https://gmail.googleapis.com/gmail/v1/users/me/labels' }
  let(:modify_url) { "https://gmail.googleapis.com/gmail/v1/users/me/messages/#{gmail_message_id}/modify" }

  before do
    refresh_service = instance_double(Google::RefreshOauthTokenService, access_token: access_token)
    allow(Google::RefreshOauthTokenService).to receive(:new).with(channel: channel).and_return(refresh_service)
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
        stub_request(:get, labels_url)
          .with(headers: { 'Authorization' => "Bearer #{access_token}" })
          .to_return(status: 200, body: { labels: [{ id: label_id, name: 'CHATWOOT_FETCHED' }] }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        stub_request(:get, list_url)
          .with(query: hash_including('q' => 'newer_than:1d in:inbox -label:CHATWOOT_FETCHED'))
          .to_return(status: 200, body: { messages: [{ id: gmail_message_id }] }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        stub_request(:get, get_url)
          .with(query: hash_including('format' => 'raw'))
          .to_return(status: 200, body: { raw: Base64.urlsafe_encode64(eml_content) }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        stub_request(:post, modify_url)
          .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns parsed Mail objects for new messages' do
        result = described_class.new(channel: channel, interval: 1).perform

        expect(result.length).to eq(1)
        expect(result.first.message_id).to eq('6215e5ca3e3b2_10bc6197e4224d1@tejaswinis-MacBook-Pro.local.mail')
      end

      it 'marks the fetched message with the CHATWOOT_FETCHED label' do
        described_class.new(channel: channel, interval: 1).perform

        expect(WebMock).to have_requested(:post, modify_url)
          .with(body: { addLabelIds: [label_id] }.to_json)
      end

      it 'creates the fetched label if it does not exist' do
        stub_request(:get, labels_url)
          .to_return(status: 200, body: { labels: [] }.to_json, headers: { 'Content-Type' => 'application/json' })

        stub_request(:post, labels_url)
          .to_return(status: 200, body: { id: label_id, name: 'CHATWOOT_FETCHED' }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        described_class.new(channel: channel, interval: 1).perform

        expect(WebMock).to have_requested(:post, labels_url)
          .with(body: hash_including(name: 'CHATWOOT_FETCHED'))
      end

      it 'skips messages already present in the inbox' do
        create(:message,
               source_id: '6215e5ca3e3b2_10bc6197e4224d1@tejaswinis-MacBook-Pro.local.mail',
               inbox: channel.inbox, account: account)

        result = described_class.new(channel: channel, interval: 1).perform

        expect(result).to eq([])
        expect(WebMock).not_to have_requested(:post, modify_url)
      end
    end

    context 'when the API returns an auth error' do
      before do
        stub_request(:get, labels_url)
          .to_return(status: 200, body: { labels: [{ id: label_id, name: 'CHATWOOT_FETCHED' }] }.to_json,
                     headers: { 'Content-Type' => 'application/json' })

        stub_request(:get, list_url)
          .to_return(status: 401, body: { error: { code: 401, message: 'unauthorized' } }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'raises OAuth2::Error so the job marks the channel for reauthorization' do
        expect { described_class.new(channel: channel, interval: 1).perform }.to raise_error(OAuth2::Error)
      end
    end
  end
end
