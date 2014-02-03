require 'spec_helper'

require 'faraday'
require 'openstudio-analysis'
require 'openstudio-aws'

describe "AmiIntegration" do
  context "most recent AMIs" do
    before(:all) do
      aws_options = {:ami_lookup_version => 2}
      @aws = OpenStudio::Aws::Aws.new(aws_options)
    end
    
    it "should have the most recent AMIs" do
      puts @aws.default_amis
      expect(@aws.default_amis).not_to be_nil
    end

    it "should create a cluster and submit a job" do
      # use the default instance type
      server_options = {instance_type: "m1.large"}

      @aws.create_server(server_options)
      expect(@aws.os_aws.server).not_to be_nil

      worker_options = {instance_type: "m1.large"}

      @aws.create_workers(1, worker_options)

      expect(@aws.os_aws.workers).to have(1).thing
      expect(@aws.os_aws.workers[0].data[:dns]).not_to be_nil

      # use faraday to do the test here
      f = Faraday.new(:url => "http://#{@aws.os_aws.server.data[:dns]}") do |faraday|
        faraday.request :url_encoded # form-encode POST params
        faraday.response :logger
        faraday.adapter Faraday.default_adapter # make requests with Net::HTTP
      end
      
      res = f.get('/')
      expect(res.status).to eq(200)
      expect(res.body).to include "OpenStudio Cloud Management Console"
      
      puts Dir.pwd
      test_file = File.expand_path("../testing/run_demo_examples.rb")
      puts test_file
      if File.exists?(test_file)
        call_cmd = "cd ../testing && bundle exec ruby #{test_file} 'http://#{@aws.os_aws.server.data[:dns]}'" 
        puts "Calling: #{call_cmd}"
        
        res = system(call_cmd)

        exitcode = $?.exitstatus
        expect(exitcode).to eq(0)
        
      end
      puts res
    end

    it "should be able to ping the server" do
    end
    
    it "should be able to load the server/worker from file" do
    end
    
    #it "should be able to submit a project and analysis" do
    #  # how to test this?
    #end
    #
    #it "should kill running instances" do
    #  # how to test this?
    #end
  end
  
  context "fixed AMI versions" do
    before(:all) do
      aws_options = {:ami_lookup_version => 2, :openstudio_server_version => "1.3.1"}
      @aws = OpenStudio::Aws::Aws.new(aws_options)
    end
    
    it "should have fixed AMIs" do
      expect(@aws.default_amis[:cc2worker]).to eq("ami-4bbb8722")
      expect(@aws.default_amis[:server]).to eq("ami-a9bb87c0")
      expect(@aws.default_amis[:worker]).to eq("ami-39bb8750")
    end
  end
end
