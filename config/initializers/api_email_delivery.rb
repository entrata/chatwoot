Rails.application.config.after_initialize do
  ActionMailer::Base.add_delivery_method :gmail_api, Mail::GmailApiDelivery
  ActionMailer::Base.add_delivery_method :microsoft_graph, Mail::MicrosoftGraphDelivery
end
