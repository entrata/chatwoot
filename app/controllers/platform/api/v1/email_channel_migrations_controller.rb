class Platform::Api::V1::EmailChannelMigrationsController < PlatformController
  before_action :set_account
  before_action :validate_account_permissible
  before_action :validate_feature_flag
  before_action :set_inbox, only: [:update]
  before_action :validate_params, only: [:create]
  before_action :validate_update_params, only: [:update]

  def create
    results = migrate_email_channels
    render json: { results: results }, status: :ok
  end

  def update
    result = update_migrated_inbox
    render json: { results: [result] }, status: :ok
  end

  private

  # PlatformController runs set_resource + validate_platform_app_permissible for #update.
  def set_resource
    @resource = Account.find(params[:account_id])
  end

  def set_account
    @account = @resource || Account.find(params[:account_id])
  end

  def validate_account_permissible
    return if @platform_app.platform_app_permissibles.find_by(permissible: @account)

    render json: { error: 'Non permissible resource' }, status: :unauthorized
  end

  def validate_feature_flag
    return if ActiveModel::Type::Boolean.new.cast(ENV.fetch('EMAIL_CHANNEL_MIGRATION', false))

    render json: { error: 'Email channel migration is not enabled' }, status: :forbidden
  end

  def set_inbox
    @inbox = @account.inboxes.find_by(id: params[:inbox_id])
    return if @inbox&.channel.is_a?(Channel::Email)

    render json: { error: 'Email channel inbox not found' }, status: :not_found
  end

  def validate_params
    return render json: { error: 'Missing migrations parameter' }, status: :unprocessable_entity if migration_params.blank?

    return unless migration_params.size > MAX_MIGRATIONS

    return render json: { error: "Too many migrations (max #{MAX_MIGRATIONS})" },
                  status: :unprocessable_entity
  end

  def validate_update_params
    return if update_migration_params.present?

    render json: { error: 'Missing migration parameter' }, status: :unprocessable_entity
  end

  def migrate_email_channels
    migration_params.map { |entry| migrate_single(entry) }
  end

  MIGRATION_ENTRY_KEYS = %i[
    email provider provider_config imap_enabled imap_address imap_port imap_login imap_enable_ssl
  ].freeze

  def update_migrated_inbox
    entry = update_migration_params
    channel = @inbox.channel
    if entry.key?(:provider) && entry[:provider].present?
      validate_provider!(entry[:provider])
    end

    result = ActiveRecord::Base.transaction do
      channel_attrs = channel_update_attrs_from_entry(entry)
      channel.update!(channel_attrs) if channel_attrs.any?

      if entry.key?(:inbox_name) && entry[:inbox_name].present?
        @inbox.update!(name: entry[:inbox_name])
      end

      { email: channel.email, inbox_id: @inbox.id, channel_id: channel.id, status: 'success' }
    end

    # When provider_config is rotated, treat this as a successful reauthorization:
    # clears the reauthorization_required / auth error count Redis keys and bumps
    # the inbox cache key so the UI reflects the change on the next fetch.
    channel.reauthorized! if entry[:provider_config].present? && channel.respond_to?(:reauthorized!)

    result
  rescue StandardError => e
    { email: channel.email, inbox_id: @inbox.id, status: 'error', message: e.message }
  end

  def channel_update_attrs_from_entry(entry)
    slice = entry.slice(*MIGRATION_ENTRY_KEYS)
    if slice.key?(:provider_config) && slice[:provider_config]
      provider = entry[:provider] || @inbox.channel.provider
      config = slice[:provider_config].to_h
      config['api_mode'] = 'rest' if SUPPORTED_PROVIDERS.include?(provider)
      slice = slice.merge(provider_config: config)
    end
    slice.compact
  end

  MAX_MIGRATIONS = 25
  SUPPORTED_PROVIDERS = %w[google microsoft].freeze

  def migrate_single(entry)
    validate_provider!(entry[:provider])

    ActiveRecord::Base.transaction do
      channel = create_channel(entry)
      inbox = create_inbox(channel, entry)

      { email: entry[:email], inbox_id: inbox.id, channel_id: channel.id, status: 'success' }
    end
  rescue StandardError => e
    { email: entry[:email], status: 'error', message: e.message }
  end

  def create_channel(entry)
    Channel::Email.create!(
      account_id: @account.id,
      email: entry[:email],
      provider: entry[:provider],
      provider_config: build_provider_config(entry),
      imap_enabled: entry.fetch(:imap_enabled, true),
      imap_address: entry[:imap_address] || default_imap_address(entry[:provider]),
      imap_port: entry[:imap_port] || 993,
      imap_login: entry[:imap_login] || entry[:email],
      imap_enable_ssl: entry.fetch(:imap_enable_ssl, true)
    )
  end

  def build_provider_config(entry)
    config = entry[:provider_config]&.to_h || {}
    config['api_mode'] = 'rest' if SUPPORTED_PROVIDERS.include?(entry[:provider])
    config
  end

  def create_inbox(channel, entry)
    @account.inboxes.create!(
      name: entry[:inbox_name] || "Migrated #{entry[:provider]&.capitalize}: #{entry[:email]}",
      channel: channel
    )
  end

  def validate_provider!(provider)
    return if SUPPORTED_PROVIDERS.include?(provider)

    raise ArgumentError, "Unsupported provider '#{provider}'. Must be one of: #{SUPPORTED_PROVIDERS.join(', ')}"
  end

  def default_imap_address(provider)
    case provider
    when 'google' then 'imap.gmail.com'
    when 'microsoft' then 'outlook.office365.com'
    else ''
    end
  end

  def migration_params
    params.permit(migrations: [
                    :email, :provider, :inbox_name,
                    :imap_enabled, :imap_address, :imap_port, :imap_login, :imap_enable_ssl,
                    { provider_config: {} }
                  ])[:migrations]
  end

  def update_migration_params
    h = params.permit(migration: [
                        :email, :provider, :inbox_name,
                        :imap_enabled, :imap_address, :imap_port, :imap_login, :imap_enable_ssl,
                        { provider_config: {} }
                      ])[:migration]
    return {} if h.blank?

    h.to_h.deep_symbolize_keys
  end
end
