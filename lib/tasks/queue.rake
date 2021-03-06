namespace :queue do
  desc "Watch the queue, and print messages on the console"
  task watcher: :environment do
    config = YAML.load_file(Rails.root.join("config", "rabbitmq.yml"))[Rails.env].symbolize_keys

    conn = Bunny.new(config)
    conn.start

    ch = conn.create_channel
    ex = ch.topic(config[:exchange], passive: true)
    q = ch.queue("", exclusive: true)
    q.bind(ex, routing_key: '#')

    at_exit do
      puts "Closing channel"
      ch.close
      conn.close
    end

    puts "Listening for messages"
    q.subscribe(block: true) do |delivery_info, properties, payload|
      puts <<-EOT.strip_heredoc
        ----- New Message -----
        Routing_key: #{delivery_info.routing_key}
        Properties: #{properties.inspect}
        Payload: #{payload}
      EOT
    end
  end

  desc "Add published editions to the message queue by document type"
  task :requeue_document_type, [:document_type] => :environment do |_, args|
    document_type = args[:document_type]
    raise ValueError("expecting document_type") unless document_type.present?

    scope = Edition
      .with_document
      .with_unpublishing
      .where(document_type: document_type)

    RequeueContent.new(scope).call
  end

  desc "Preview of the message published onto rabbit MQ"
  task :preview_recent_message, [:document_type] => :environment do |_, args|
    document_type = args[:document_type]
    raise ValueError("expecting document_type") unless document_type.present?

    edition = Edition
              .with_document
              .order(public_updated_at: :desc)
              .find_by!(
                editions: { state: 'published' },
                document_type: document_type
              )
    version = Event.maximum(:id)

    presenter = DownstreamPayload.new(edition, version, draft: false)
    payload = presenter.message_queue_payload

    pp payload
  end
end
