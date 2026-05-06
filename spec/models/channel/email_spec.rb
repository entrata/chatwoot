# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe Channel::Email do
  let(:channel) { create(:channel_email) }

  describe 'concerns' do
    it_behaves_like 'reauthorizable'

    context 'when prompt_reauthorization!' do
      it 'calls channel notifier mail for email' do
        admin_mailer = double
        mailer_double = double
        expect(AdministratorNotifications::ChannelNotificationsMailer).to receive(:with).and_return(admin_mailer)
        expect(admin_mailer).to receive(:email_disconnect).with(channel.inbox).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)
        channel.prompt_reauthorization!
      end
    end
  end

  it 'has a valid name' do
    expect(channel.name).to eq('Email')
  end

  context 'when microsoft?' do
    it 'returns false' do
      expect(channel.microsoft?).to be(false)
    end

    it 'returns true' do
      channel.provider = 'microsoft'
      expect(channel.microsoft?).to be(true)
    end
  end

  context 'when google?' do
    it 'returns false' do
      expect(channel.google?).to be(false)
    end

    it 'returns true' do
      channel.provider = 'google'
      expect(channel.google?).to be(true)
    end
  end

  describe '#rest_api_mode?' do
    it 'returns false when provider_config is empty' do
      expect(channel.rest_api_mode?).to be(false)
    end

    it 'returns false when api_mode is not rest' do
      channel.provider_config = { 'access_token' => 'x' }
      expect(channel.rest_api_mode?).to be(false)
    end

    it 'returns true when api_mode is rest' do
      channel.provider_config = { 'access_token' => 'x', 'api_mode' => 'rest' }
      expect(channel.rest_api_mode?).to be(true)
    end
  end

  describe '#inbound_fetch_enabled?' do
    it 'is true when IMAP is enabled' do
      channel.imap_enabled = true
      channel.provider_config = {}
      expect(channel.inbound_fetch_enabled?).to be(true)
    end

    it 'is true when REST API mode is on even if IMAP is disabled' do
      channel.imap_enabled = false
      channel.provider_config = { 'api_mode' => 'rest', 'refresh_token' => 'x' }
      expect(channel.inbound_fetch_enabled?).to be(true)
    end

    it 'is false when neither IMAP nor REST fetch is configured' do
      channel.imap_enabled = false
      channel.provider_config = {}
      expect(channel.inbound_fetch_enabled?).to be(false)
    end

    it 'is true when Google OAuth has a refresh token but IMAP is disabled (no api_mode rest)' do
      channel.imap_enabled = false
      channel.provider = 'google'
      channel.provider_config = {
        'access_token' => 'x',
        'refresh_token' => 'y',
        'expires_on' => 1.hour.from_now.to_s
      }
      expect(channel.inbound_fetch_enabled?).to be(true)
      expect(channel.gmail_api_inbound?).to be(true)
    end
  end

  describe '#gmail_api_inbound? and #microsoft_graph_inbound?' do
    it 'prefers Gmail API when REST is set even if IMAP is on' do
      channel.provider = 'google'
      channel.imap_enabled = true
      channel.provider_config = { 'api_mode' => 'rest', 'refresh_token' => 'x' }
      expect(channel.gmail_api_inbound?).to be(true)
    end
  end
end
