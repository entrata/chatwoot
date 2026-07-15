module Email::OauthSmtpRetrier
  module_function

  # Yields the block. If SMTP fails with an auth error (e.g. Gmail 535-5.7.8) on a
  # Google/Microsoft email channel, refreshes the channel's OAuth access token and
  # retries the block once.
  #
  # On a successful retry, clears any stale `reauthorization_required` flag on the
  # channel so the UI no longer shows it as disconnected. If the refresh itself
  # fails (OAuth2::Error) or the retry still hits an auth error, ticks the channel's
  # authorization error counter so the existing disconnect threshold (see
  # `Reauthorizable#authorization_error!`) eventually marks the channel disconnected.
  def with_retry(channel)
    result = yield
    clear_stale_reauth_flag(channel)
    result
  rescue Net::SMTPAuthenticationError => e
    raise e unless oauth_email_channel?(channel)

    refresh_and_retry(channel) { yield }
  end

  def refresh_and_retry(channel)
    refresh_channel_oauth_token(channel)
    result = yield
    clear_stale_reauth_flag(channel)
    result
  rescue Net::SMTPAuthenticationError, OAuth2::Error => e
    channel.authorization_error!
    raise e
  end

  # If a previous OAuth/IMAP failure left the channel flagged for reauthorization
  # but a real send just succeeded, the credentials are clearly working - clear
  # the stale flag so the UI stops showing it as disconnected.
  def clear_stale_reauth_flag(channel)
    return unless oauth_email_channel?(channel)
    return unless channel.reauthorization_required?

    channel.reauthorized!
  end

  def oauth_email_channel?(channel)
    channel.is_a?(Channel::Email) && (channel.google? || channel.microsoft?)
  end

  def refresh_channel_oauth_token(channel)
    service_class = channel.google? ? Google::RefreshOauthTokenService : Microsoft::RefreshOauthTokenService
    service_class.new(channel: channel).refresh_tokens
  end
end
