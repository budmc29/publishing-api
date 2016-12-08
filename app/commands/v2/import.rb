module Commands
  module V2
    class Import < BaseCommand

      def self.call(payload)
        logger.debug "#{self} called with payload:\n#{payload}"

        response = ContentItem.transaction do
          PublishingAPI.service(:statsd).time(self.name.gsub(/:+/, '.')) do
            new(payload, event: nil, downstream: true, nested: false, callbacks: []).call
          end
        end

        response
      end

      def call
        unless UuidValidator.valid?(payload[:content_id])
          raise CommandError.new(
          code: 422,
          error_details: {
            error: {
              code: 422,
              message: "Content id not valid",
              fields: "content_id",
            }
          })
        end

        delete_all(payload[:content_id])
        all_content_items.map.with_index do |event, index|
          create_content_item(event, index, payload[:content_id])
        end

        send_downstream(all_content_items.find { |e| e[:action] == 'Publish' })

        Success.new(content_id: payload[:content_id])
      end

    private

      def all_content_items
        @all_content_items ||= [redirects.compact + payload[:content_items]].flatten
      end

      def send_downstream(content)
        return unless content
        DownstreamLiveWorker.perform_async_in_queue(
          DownstreamLiveWorker::LOW_QUEUE,
          content_id: content[:content_id],
          locale: 'en',
          message_queue_update_type: content[:payload][:update_type],
          payload_version: 1 #event.id
        )
      end

      def create_content_item(event, index, content_id)
        event_payload = event[:payload].slice(*attributes)
        validate_schema(event_payload)
        event_payload.merge(content_id: content_id)
        Services::CreateContentItem.new(
          payload: event_payload,
          user_facing_version: index + 1,
          lock_version: index + 1,
          state: state(event)
        ).create_content_item
      end

      def attributes
        @attributes ||= ContentItem.new.attributes.keys.map(&:to_sym) << :base_path
      end

      def state(event)
        event[:payload][:state] || 'superseded'
      end

      def redirects
        return [] if base_paths_and_routes.count == 1
        base_paths_and_routes.map.with_index do |(base_path, routes), index|
          new_base_path = base_paths_and_routes[index + 1]
          next unless new_base_path
          {
            payload: RedirectHelper.create_redirect(
              publishing_app: publishing_app,
              old_base_path: base_path,
              new_base_path: new_base_path.first,
              routes: routes,
              options: { skip_put_content: true }, callbacks: nil,
            )
          }
        end
      end

      def publishing_app
        @payload[:content_items].map { |e| e[:payload][:publishing_app] }.last
      end

      def base_paths_and_routes
        @base_paths ||= payload[:content_items].map { |e| [e[:payload][:base_path], e[:payload][:routes]] }.uniq
      end

      def delete_all(content_id)
        Services::DeleteContentItem.destroy_content_items_with_links(content_id)
      end

      def validate_schema(payload)
        schema_validator = SchemaValidator.new(payload: payload.except(:content_id))
        return if schema_validator.valid?
        message = "The payload did not conform to the schema"
        raise CommandError.new(
          code: 422,
          message: message,
          error_details: schema_validator.errors,
        )
      end
    end
  end
end
