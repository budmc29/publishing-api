module Tasks
  class SplitDates
    def self.populate
      count = Document.count
      start = Time.now
      Document.eager_load(:editions).find_each.with_index do |document, index|
        populate_dates_for_document(document)
        completed = index + 1
        if completed % 100 == 0
          seconds_elapsed = Time.now.to_i - start.to_i
          per_second = seconds_elapsed.to_f / completed
          remaining_time = per_second * (count - completed)

          # This won't work if it's over 24 hours, but that's probably a bigger problem
          time = Time.at(remaining_time).utc.strftime("%H:%M:%S")

          puts "Progress: #{completed}/#{count} documents, approximately #{time} remaining."
        end
      end
      puts "Completed populating dates"
    end

    def self.populate_dates_for_document(document)
      document.editions.sort { |e| -e.user_facing_version }.each do |edition|
        PopulateEdition.new(edition).call
        edition.save if edition.changed?
      end
    end

    def self.reset_document(document)
      document.editions.each do |edition|
        edition.update(
          temporary_first_published_at: nil,
          publisher_first_published_at: nil,
          major_published_at: nil,
          publisher_major_published_at: nil,
          published_at: nil,
          publisher_published_at: nil,
          temporary_last_edited_at: nil,
          publisher_last_edited_at: nil
        )
      end
    end
  end
end
