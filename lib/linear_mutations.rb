module LinearMutations
  def self.graphql_value(value)
    case value
    when String
      # Strings must be enclosed in double quotes
      "\"#{value}\""
    when Array
      # Arrays need to be recursively converted
      "[#{value.map { |v| graphql_value(v) }.join(', ')}]"
    else
      # Other types (numbers, booleans) can be directly converted to strings
      value.to_s
    end
  end

  def self.graphql_input(input)
    input.map { |key, value| "#{key}: #{graphql_value(value)}" }.join(', ')
  end

  # Main mutation creation function
  def self.issue_create(input)
    <<~GRAPHQL
      mutation {
        issueCreate(input: { #{graphql_input(input)} }) {
          success
          issue {
            id
            title
          }
        }
      }
    GRAPHQL
  end

  def self.issue_link(issue_id, link)
    <<~GRAPHQL
      mutation {
        attachmentLinkURL(url: "#{link}", issueId: "#{issue_id}") {
          success
          attachment {
            id
          }
        }
      }
    GRAPHQL
  end
end