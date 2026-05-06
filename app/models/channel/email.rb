# == Schema Information
#
# Table name: channel_email
#
#  id                        :bigint           not null, primary key
#  email                     :string           not null
#  forward_to_email          :string           not null
#  imap_address              :string           default("")
#  imap_enable_ssl           :boolean          default(TRUE)
#  imap_enabled              :boolean          default(FALSE)
#  imap_login                :string           default("")
#  imap_password             :string           default("")
#  imap_port                 :integer          default(0)
#  provider                  :string
#  provider_config           :jsonb
#  smtp_address              :string           default("")
#  smtp_authentication       :string           default("login")
#  smtp_domain               :string           default("")
#  smtp_enable_ssl_tls       :boolean          default(FALSE)
#  smtp_enable_starttls_auto :boolean          default(TRUE)
#  smtp_enabled              :boolean          default(FALSE)
#  smtp_login                :string           default("")
#  smtp_openssl_verify_mode  :string           default("none")
#  smtp_password             :string           default("")
#  smtp_port                 :integer          default(0)
#  verified_for_sending      :boolean          default(FALSE), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :integer          not null
#
# Indexes
#
#  index_channel_email_on_email             (email) UNIQUE
#  index_channel_email_on_forward_to_email  (forward_to_email) UNIQUE
#

class Channel::Email < ApplicationRecord
  include Channelable
  include Reauthorizable

  AUTHORIZATION_ERROR_THRESHOLD = 10

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  if Chatwoot.encryption_configured?
    encrypts :imap_password
    encrypts :smtp_password
  end

  self.table_name = 'channel_email'
  EDITABLE_ATTRS = [:email, :imap_enabled, :imap_login, :imap_password, :imap_address, :imap_port, :imap_enable_ssl,
                    :smtp_enabled, :smtp_login, :smtp_password, :smtp_address, :smtp_port, :smtp_domain, :smtp_enable_starttls_auto,
                    :smtp_enable_ssl_tls, :smtp_openssl_verify_mode, :smtp_authentication, :provider, :verified_for_sending].freeze

  validates :email, uniqueness: true
  validates :forward_to_email, uniqueness: true

  before_validation :ensure_forward_to_email, on: :create

  def name
    'Email'
  end

  def microsoft?
    provider == 'microsoft'
  end

  def google?
    provider == 'google'
  end

  def legacy_google?
    imap_enabled && imap_address == 'imap.gmail.com'
  end

  def rest_api_mode?
    provider_config.is_a?(Hash) && provider_config['api_mode'] == 'rest'
  end

  # Inbound mail via Gmail API / Microsoft Graph (explicit `api_mode: rest` or OAuth with IMAP off).
  def gmail_api_inbound?
    google? && (rest_api_mode? || oauth_mail_api_inbound_without_imap?)
  end

  def microsoft_graph_inbound?
    microsoft? && (rest_api_mode? || oauth_mail_api_inbound_without_imap?)
  end

  # Scheduled inbound fetch: IMAP (password or XOAUTH), REST flag, or OAuth with IMAP disabled
  # (same mail APIs as REST—avoids requiring IMAP toggled on in the UI for Google/Microsoft OAuth).
  def inbound_fetch_enabled?
    imap_enabled? || rest_api_mode? || oauth_mail_api_inbound_without_imap?
  end

  private

  def oauth_mail_api_inbound_without_imap?
    return false if imap_enabled?
    return false unless provider_config.is_a?(Hash) && provider_config['refresh_token'].present?

    google? || microsoft?
  end

  def ensure_forward_to_email
    self.forward_to_email ||= "#{SecureRandom.hex}@#{account.inbound_email_domain}"
  end
end
