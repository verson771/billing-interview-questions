# called with ReportsHandler.new("zadara").handle
require "s3_files"

class ReportsHandler
  def initialize(options = {})
    @bucket = options[:bucket]
    @s3_service = ENV["USE_S3"] ? S3.new : S3Files.new
    @status_to_event_mapping = {
      "created" => "restored",
      "active" => "restored",
      "missing delete event" => "missing delete event from s3/ files"
    }
  end

  def handle
    @object_list = download_reports_list
    @reports = download_and_parse_reports
    @missing_event_handled = handle_missing_events(2)
    @marked_event_deleted = mark_missing_event_as_deleted(false)
  end

  def download_reports_list
    @s3_service.list(bucket: @bucket)
    # Response is {cluster_id}/{type}.{uuid}.{datetime}.json
    # Example response
    #
    # [
    #   1234-1234-1234-1234/VM.5678-5678-5678-5678.20220122T11:22:33Z.json
    # ]
  end

  def download_and_parse_reports
    @object_list.each do |object|
      options = {
        bucket: @bucket,
        object: object,
      }
      body = @s3_service.download(options)
      # Example Body
      #  {
      #     cluster_uuid: "1234-1234-1234-1234",
      #     uuid: "5678-5678-5678-5678",
      #     status: "active"
      #  }
      handle_report(body)

      # We don't want to process the same report
      @s3_service.delete(options)
    end
  end

  def handle_report(body)
    json = JSON.parse(body).symbolize_keys
    compute_cluster = ComputeCluster.find_or_create_by(uuid: json[:cluster_uuid])
    compute_cluster.name = json[:cluster_name]
    compute_cluster.save
    vm = VirtualMachine.find_by(uuid: json[:uuid])
    if !vm
      vm = VirtualMachine.create(uuid: json[:uuid], compute_cluster_id: compute_cluster.id, status: "active", name: json[:name])
      Event.create(virtual_machine_id: vm.id, event_type: "created", created_at: Time.now)
      return
    end
    current_status = vm.status
    print("current_status #{current_status}")
    print("@status_to_event_mapping[current_status] #{@status_to_event_mapping[current_status]}")

    if vm && current_status != json[:status]
      Event.create(virtual_machine_id: vm.id, event_type: @status_to_event_mapping[json[:status]], created_at: Time.now)
      #vm.status = current_status
      vm.status = json[:status]
      vm.save
    end
  end
  def handle_missing_events(cutoffDays)
    return if cutoffDays.nil? || cutoffDays.negative?

    cutOffDate = DateTime.now.advance(days: cutoffDays * -1)

    # find VM list with no update from S3/files since the cut off days
    # and update status = 'missing delete event'
    missingEventVMList = VirtualMachine.where("status = :status", :status => 'active')
                                     .where("updated_at <= :cutoffDate", :cutoffDate => cutOffDate)

    missingEventVMList.each do |vm|
      updateTime = Time.now
      deleteStatus = 1
      vmStatus = "missing delete event"
      Event.create(virtual_machine_id: vm.id, event_type: vmStatus, created_at: updateTime)
      vm.update_columns(status: vmStatus, updated_at: updateTime)
      vm.save
    end
    true
  end

  def mark_missing_event_as_deleted(deleteAction)
    return if deleteAction.nil? || deleteAction == false

    missingDeleteEventStatus = 'missing delete event'
    deleteStatus = 'deleted'

    # find list of VM with status of 'missing delete event status then update status = deleted'
    missingVMList = VirtualMachine.where("status = :status", :status => missingDeleteEventStatus)

    missingVMList.each do |vm|
      deleteTime = Time.now
      deleteStatusCode = 1
      Event.create(virtual_machine_id: vm.id, event_type: deleteStatus, created_at: deleteTime)
      vm.status = missingDeleteEventStatus
      vm.update_columns(status: deleteStatus, deleted: deleteStatusCode, deleted_at: deleteTime, updated_at: deleteTime)
      vm.save
    end
    true
  end
end
