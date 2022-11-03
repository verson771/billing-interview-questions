task :fetch_and_process => [:environment] do
  ReportsHandler.new.handle
end
