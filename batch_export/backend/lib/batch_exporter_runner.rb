require_relative 'job_runner'
require_relative "../exporters/lib/exporter"
require_relative 'AS_fop'


class BatchExportRunner < JobRunner
  include JSONModel


  def self.instance_for(job)
    if job.job_type == "batch_export_job"
      self.new(job)
    else
      nil
    end
  end
 

  def run
    super
    begin 
	  Log.debug("PRETEND")
      RequestContext.open( :repo_id => @job.repo_id) do
        # why does this not work?
        #resource= JSONModel(:resource).find_by_uri(@json.job["source"])
       
        parsed = JSONModel.parse_reference(@json.job["resources"])
        resource = Resource.to_jsonmodel(parsed[:id]) 
        

        @job.write_output("Generating PDF for #{resource["title"]}  ")
        
        obj = URIResolver.resolve_references(resource,
                                                [ "repository", "linked_agents", "subjects", "tree",  "digital_objects"],
                                                { 'rack.input' => "",  'QUERY_STRING' => "" })
        opts = {
          :include_unpublished => true,
          :include_daos => true,
          :use_numbered_c_tags => false 
        }
        
        record = JSONModel(:resource).new(obj) 
        ead = ASpaceExport.model(:ead).from_resource( record, opts)
        xml = "" 
        ASpaceExport.stream(ead).each { |x| xml << x }
        pdf = ASFop.new(xml).to_pdf  
        job_file = @job.add_file( pdf )
        @job.write_output("File generated at #{job_file['file_path'].inspect} ")
        pdf.unlink
        @job.record_modified_uris( [@json.job["resources"]] ) 
        @job.write_output("All done. Please click refresh to view your download link.")
        self.success!
        job_file
      end 
    rescue Exception => e
      @job.write_output(e.message)
      @job.write_output(e.backtrace)
      raise e 
    end 
  end


end