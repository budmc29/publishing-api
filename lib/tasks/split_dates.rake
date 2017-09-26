namespace :split_dates do
  # @TODO Remove this task once it has been run
  desc "Populate the split dates introduced September 2017"
  task populate: :environment do
    Tasks::SplitDates.populate
  end
end
