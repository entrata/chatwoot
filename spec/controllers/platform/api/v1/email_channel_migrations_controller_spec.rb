require 'rails_helper'

RSpec.describe 'Platform Email Channel Migrations API', type: :request do
  let!(:account) { create(:account) }
  let(:platform_app) { create(:platform_app) }
  let(:base_url) { "/platform/api/v1/accounts/#{account.id}/email_channel_migrations" }
  let(:headers) { { api_access_token: platform_app.access_token.token } }

  let(:google_provider_config) do
    { access_token: 'ya29.test-access-token', refresh_token: '1//test-refresh-token', expires_on: 1.hour.from_now.to_s }
  end

  let(:valid_migration_params) do
    {
      migrations: [
        {
          email: 'support@example.com',
          provider: 'google',
          provider_config: google_provider_config,
          inbox_name: 'Migrated Support'
        }
      ]
    }
  end

  before do
    create(:platform_app_permissible, platform_app: platform_app, permissible: account)
  end

  describe 'POST /platform/api/v1/accounts/:account_id/email_channel_migrations' do
    context 'when unauthenticated' do
      it 'returns unauthorized without token' do
        with_modified_env EMAIL_CHANNEL_MIGRATION: 'true' do
          post base_url, as: :json
          expect(response).to have_http_status(:unauthorized)
        end
      end

      it 'returns unauthorized with invalid token' do
        with_modified_env EMAIL_CHANNEL_MIGRATION: 'true' do
          post base_url, params: valid_migration_params, headers: { api_access_token: 'invalid' }, as: :json
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end

    context 'when account is not permissible' do
      let(:other_account) { create(:account) }
      let(:other_url) { "/platform/api/v1/accounts/#{other_account.id}/email_channel_migrations" }

      it 'returns unauthorized' do
        with_modified_env EMAIL_CHANNEL_MIGRATION: other_account.id.to_s do
          post other_url, params: valid_migration_params, headers: headers, as: :json
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end

    context 'when account is not in allowed list' do
      it 'returns forbidden' do
        with_modified_env EMAIL_CHANNEL_MIGRATION: '' do
          post base_url, params: valid_migration_params, headers: headers, as: :json
          expect(response).to have_http_status(:forbidden)
          expect(response.parsed_body['error']).to eq('Email channel migration is not enabled')
        end
      end
    end

    context 'when authenticated with permissible account' do
      around do |example|
        with_modified_env EMAIL_CHANNEL_MIGRATION: 'true' do
          example.run
        end
      end

      it 'creates a google email channel and inbox' do
        expect do
          post base_url, params: valid_migration_params, headers: headers, as: :json
        end.to change(Channel::Email, :count).by(1).and change(Inbox, :count).by(1)

        expect(response).to have_http_status(:ok)
        result = response.parsed_body['results'].first
        expect(result['status']).to eq('success')
        expect(result['email']).to eq('support@example.com')
        expect(result['inbox_id']).to be_present
        expect(result['channel_id']).to be_present
      end

      it 'sets correct google channel attributes' do
        post base_url, params: valid_migration_params, headers: headers, as: :json

        channel = Channel::Email.find(response.parsed_body['results'].first['channel_id'])
        expect(channel.provider).to eq('google')
        expect(channel.imap_enabled).to be(true)
        expect(channel.imap_address).to eq('imap.gmail.com')
        expect(channel.imap_port).to eq(993)
        expect(channel.imap_login).to eq('support@example.com')
        expect(channel.provider_config['refresh_token']).to eq('1//test-refresh-token')
      end

      it 'sets correct inbox attributes' do
        post base_url, params: valid_migration_params, headers: headers, as: :json

        inbox = Inbox.find(response.parsed_body['results'].first['inbox_id'])
        expect(inbox.name).to eq('Migrated Support')
        expect(inbox.account_id).to eq(account.id)
      end

      it 'creates a microsoft email channel with correct defaults' do
        params = {
          migrations: [
            {
              email: 'support@outlook.com',
              provider: 'microsoft',
              provider_config: { access_token: 'test', refresh_token: 'test', expires_on: 1.hour.from_now.to_s }
            }
          ]
        }

        post base_url, params: params, headers: headers, as: :json

        expect(response).to have_http_status(:ok)
        result = response.parsed_body['results'].first
        channel = Channel::Email.find(result['channel_id'])

        expect(channel.provider).to eq('microsoft')
        expect(channel.imap_address).to eq('outlook.office365.com')
      end

      it 'uses default inbox name when not provided' do
        params = { migrations: [{ email: 'test@example.com', provider: 'google', provider_config: google_provider_config }] }

        post base_url, params: params, headers: headers, as: :json

        inbox = Inbox.find(response.parsed_body['results'].first['inbox_id'])
        expect(inbox.name).to eq('Migrated Google: test@example.com')
      end

      it 'defaults imap_login to email address' do
        post base_url, params: valid_migration_params, headers: headers, as: :json

        channel = Channel::Email.find(response.parsed_body['results'].first['channel_id'])
        expect(channel.imap_login).to eq('support@example.com')
      end

      it 'sets api_mode to rest on google channel provider_config' do
        post base_url, params: valid_migration_params, headers: headers, as: :json

        channel = Channel::Email.find(response.parsed_body['results'].first['channel_id'])
        expect(channel.provider_config['api_mode']).to eq('rest')
        expect(channel.rest_api_mode?).to be(true)
      end

      it 'sets api_mode to rest on microsoft channel provider_config' do
        params = {
          migrations: [
            {
              email: 'support@outlook.com',
              provider: 'microsoft',
              provider_config: { access_token: 'test', refresh_token: 'test', expires_on: 1.hour.from_now.to_s }
            }
          ]
        }

        post base_url, params: params, headers: headers, as: :json

        channel = Channel::Email.find(response.parsed_body['results'].first['channel_id'])
        expect(channel.provider_config['api_mode']).to eq('rest')
        expect(channel.rest_api_mode?).to be(true)
      end

      it 'allows overriding imap settings' do
        params = {
          migrations: [
            {
              email: 'custom@example.com',
              provider: 'google',
              provider_config: google_provider_config,
              imap_address: 'custom.imap.server.com',
              imap_port: 143,
              imap_login: 'custom-login@example.com',
              imap_enable_ssl: false
            }
          ]
        }

        post base_url, params: params, headers: headers, as: :json

        channel = Channel::Email.find(response.parsed_body['results'].first['channel_id'])
        expect(channel.imap_address).to eq('custom.imap.server.com')
        expect(channel.imap_port).to eq(143)
        expect(channel.imap_login).to eq('custom-login@example.com')
        expect(channel.imap_enable_ssl).to be(false)
      end
    end

    context 'when migrating multiple channels' do
      around do |example|
        with_modified_env EMAIL_CHANNEL_MIGRATION: 'true' do
          example.run
        end
      end

      let(:bulk_params) do
        {
          migrations: [
            { email: 'first@example.com', provider: 'google', provider_config: google_provider_config },
            { email: 'second@example.com', provider: 'google', provider_config: google_provider_config },
            { email: 'third@example.com', provider: 'microsoft',
              provider_config: { access_token: 'test', refresh_token: 'test', expires_on: 1.hour.from_now.to_s } }
          ]
        }
      end

      it 'creates all channels and inboxes' do
        expect do
          post base_url, params: bulk_params, headers: headers, as: :json
        end.to change(Channel::Email, :count).by(3).and change(Inbox, :count).by(3)

        results = response.parsed_body['results']
        expect(results.map { |r| r['status'] }).to all(eq('success'))
        expect(results.map { |r| r['email'] }).to match_array(%w[first@example.com second@example.com third@example.com])
      end

      it 'continues processing when one migration fails' do
        create(:channel_email, email: 'first@example.com', account: account)

        expect do
          post base_url, params: bulk_params, headers: headers, as: :json
        end.to change(Channel::Email, :count).by(2).and change(Inbox, :count).by(2)

        results = response.parsed_body['results']
        failed = results.find { |r| r['email'] == 'first@example.com' }
        succeeded = results.reject { |r| r['email'] == 'first@example.com' }

        expect(failed['status']).to eq('error')
        expect(failed['message']).to include('Email has already been taken')
        expect(succeeded.map { |r| r['status'] }).to all(eq('success'))
      end
    end

    context 'when params are invalid' do
      around do |example|
        with_modified_env EMAIL_CHANNEL_MIGRATION: 'true' do
          example.run
        end
      end

      it 'returns unprocessable entity when migrations param is missing' do
        post base_url, params: {}, headers: headers, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns unprocessable entity when migrations exceed max batch size' do
        params = {
          migrations: Array.new(26) { |i| { email: "user#{i}@example.com", provider: 'google', provider_config: google_provider_config } }
        }

        post base_url, params: params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('Too many migrations')
      end

      it 'returns error for unsupported provider' do
        params = {
          migrations: [{ email: 'test@example.com', provider: 'Yahoo', provider_config: google_provider_config }]
        }

        post base_url, params: params, headers: headers, as: :json

        result = response.parsed_body['results'].first
        expect(result['status']).to eq('error')
        expect(result['message']).to include("Unsupported provider 'Yahoo'")
      end

      it 'returns error for duplicate email' do
        create(:channel_email, email: 'existing@example.com', account: account)

        params = {
          migrations: [{ email: 'existing@example.com', provider: 'google', provider_config: google_provider_config }]
        }

        post base_url, params: params, headers: headers, as: :json

        result = response.parsed_body['results'].first
        expect(result['status']).to eq('error')
        expect(result['message']).to include('Email has already been taken')
      end
    end
  end

  describe 'PATCH /platform/api/v1/accounts/:account_id/email_channel_migrations/:inbox_id' do
    let!(:email_channel) { create(:channel_email, account: account) }
    let(:email_inbox) { email_channel.inbox }
    let(:patch_url) { "#{base_url}/#{email_inbox.id}" }
    let(:valid_patch_params) do
      {
        migration: {
          inbox_name: 'Renamed Inbox',
          imap_port: 143,
          provider_config: google_provider_config
        }
      }
    end

    context 'when unauthenticated' do
      it 'returns unauthorized' do
        with_modified_env EMAIL_CHANNEL_MIGRATION: 'true' do
          patch patch_url, as: :json, params: valid_patch_params
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end

    context 'when inbox is not an email channel' do
      let(:widget_inbox) { create(:inbox, account: account) }
      let(:patch_widget_url) { "#{base_url}/#{widget_inbox.id}" }

      it 'returns not found' do
        with_modified_env EMAIL_CHANNEL_MIGRATION: 'true' do
          patch patch_widget_url, headers: headers, as: :json, params: valid_patch_params
          expect(response).to have_http_status(:not_found)
        end
      end
    end

    context 'when authenticated with permissible account' do
      around do |example|
        with_modified_env EMAIL_CHANNEL_MIGRATION: 'true' do
          example.run
        end
      end

      it 'updates channel and inbox' do
        patch patch_url, headers: headers, as: :json, params: valid_patch_params

        expect(response).to have_http_status(:ok)
        result = response.parsed_body['results'].first
        expect(result['status']).to eq('success')
        expect(result['inbox_id']).to eq(email_inbox.id)

        email_inbox.reload
        email_channel.reload
        expect(email_inbox.name).to eq('Renamed Inbox')
        expect(email_channel.imap_port).to eq(143)
        expect(email_channel.provider_config['refresh_token']).to eq('1//test-refresh-token')
      end

      it 'stamps api_mode rest on provider_config when rotating google credentials' do
        email_channel.update!(provider: 'google')

        patch patch_url, headers: headers, as: :json, params: valid_patch_params

        expect(response).to have_http_status(:ok)
        expect(email_channel.reload.provider_config['api_mode']).to eq('rest')
      end

      it 'returns not found when inbox_id belongs to a different account' do
        other_inbox = create(:channel_email, account: create(:account)).inbox
        wrong_url = "/platform/api/v1/accounts/#{account.id}/email_channel_migrations/#{other_inbox.id}"

        patch wrong_url, headers: headers, as: :json, params: valid_patch_params

        expect(response).to have_http_status(:not_found)
      end

      context 'with reauthorization state' do
        before do
          # Neutralise the disconnect mailer so we can drive the channel into a
          # reauthorization-required state without exercising mailer templates.
          allow_any_instance_of(Channel::Email).to receive(:send_channel_reauthorization_email)
          email_channel.authorization_error!
          email_channel.prompt_reauthorization!
        end

        it 'clears the reauthorization_required redis flag when provider_config is rotated' do
          expect(email_channel.reauthorization_required?).to be true

          patch patch_url, headers: headers, as: :json, params: valid_patch_params

          expect(response).to have_http_status(:ok)
          expect(email_channel.reauthorization_required?).to be false
        end

        it 'resets the authorization_error_count when provider_config is rotated' do
          expect(email_channel.authorization_error_count).to be > 0

          patch patch_url, headers: headers, as: :json, params: valid_patch_params

          expect(email_channel.authorization_error_count).to eq 0
        end

        it 'does not clear the reauthorization_required flag when provider_config is absent' do
          rename_only_params = { migration: { inbox_name: 'Renamed Only', imap_port: 143 } }

          patch patch_url, headers: headers, as: :json, params: rename_only_params

          expect(response).to have_http_status(:ok)
          expect(email_channel.reauthorization_required?).to be true
        end
      end
    end
  end
end
