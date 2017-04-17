# *******************************************************************************
# OpenStudio(R), Copyright (c) 2008-2016, Alliance for Sustainable Energy, LLC.
# All rights reserved.
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# (1) Redistributions of source code must retain the above copyright notice,
# this list of conditions and the following disclaimer.
#
# (2) Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# (3) Neither the name of the copyright holder nor the names of any contributors
# may be used to endorse or promote products derived from this software without
# specific prior written permission from the respective party.
#
# (4) Other than as required in clauses (1) and (2), distributions in any form
# of modifications or other derivative works may not use the "OpenStudio"
# trademark, "OS", "os", or any other confusingly similar designation without
# specific prior written permission from Alliance for Sustainable Energy, LLC.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER, THE UNITED STATES
# GOVERNMENT, OR ANY CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
# EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# *******************************************************************************

#Particle Swarm Optimization
class AnalysisLibrary::Pso < AnalysisLibrary::Base
  include AnalysisLibrary::R::Core

  def initialize(analysis_id, analysis_job_id, options = {})
    defaults = {
      skip_init: false,
      run_data_point_filename: 'run_openstudio_workflow.rb',
      create_data_point_filename: 'create_data_point.rb',
      output_variables: [],
      problem: {
        random_seed: 1979,
        algorithm: {
          npart: 4,
          maxfn: 100,
          maxit: 20,
          abstol: 1e-2,
          reltol: 1e-2,
          method: 'spso2011',
          xini: 'lhs',
          vini: 'lhs2011',
          boundary: 'reflecting',
          topology: 'random',
          c1: 1.193147,
          c2: 1.193147,
          lambda: 0.9,
          norm_type: 'minkowski',
          p_power: 2,
          exit_on_guideline14: 0,
          debug_messages: 0,
          failed_f_value: 1e18,
          max_queued_jobs: 0,
          objective_functions: []
        }
      }
    }.with_indifferent_access # make sure to set this because the params object from rails is indifferential
    @options = defaults.deep_merge(options)

    @analysis_id = analysis_id
    @analysis_job_id = analysis_job_id
  end

  # Perform is the main method that is run in the background.  At the moment if this method crashes
  # it will be logged as a failed delayed_job and will fail after max_attempts.
  def perform
    @analysis = Analysis.find(@analysis_id)

    # get the analysis and report that it is running
    @analysis_job = AnalysisLibrary::Core.initialize_analysis_job(@analysis, @analysis_job_id, @options)

    # reload the object (which is required) because the subdocuments (jobs) may have changed
    @analysis.reload

    # Make the analysis directory if it doesn't already exist
    FileUtils.mkdir_p analysis_dir(@analysis.id) unless Dir.exist? analysis_dir(@analysis.id)

    # create an instance for R
    @r = AnalysisLibrary::Core.initialize_rserve(APP_CONFIG['rserve_hostname'],
                                                 APP_CONFIG['rserve_port'])
    logger.info 'Setting up R for PSO Run'
    # Initialize some variables that are in the rescue/ensure blocks
    cluster = nil
    begin
      @r.converse("setwd('#{APP_CONFIG['sim_root_path']}')")

      # TODO: deal better with random seeds
      @r.converse "set.seed(#{@analysis.problem['random_seed']})"
      # R libraries needed for this algorithm
      @r.converse 'library(rjson)'
      @r.converse 'library(NRELpso)'

      master_ip = 'localhost'

      logger.info("Master ip: #{master_ip}")
      logger.info('Starting PSO Run')

      # Quick preflight check that R, MongoDB, and Rails are working as expected. Checks to make sure
      # that the run flag is true.

      # TODO: preflight check -- need to catch this in the analysis module
      if @analysis.problem['algorithm']['maxit'].nil? || (@analysis.problem['algorithm']['maxit']).zero?
        raise 'Number of max iterations was not set or equal to zero (must be 1 or greater)'
      end

      # TODO: add test for not "minkowski", "maximum", "euclidean", "binary", "manhattan"
      # if @analysis.problem['algorithm']['norm_type'] != "minkowski", "maximum", "euclidean", "binary", "manhattan"
      #  raise "P Norm must be non-negative"
      # end
      unless %w(spso2007 spso2011 ipso fips wfips).include?(@analysis.problem['algorithm']['method'])
        raise 'unknown method type'
      end

      unless %w(lhs random).include?(@analysis.problem['algorithm']['xini'])
        raise 'unknown Xini type'
      end

      unless %w(zero lhs2011 random2011 lhs2007 random2007 default).include?(@analysis.problem['algorithm']['vini'])
        raise 'unknown Vini type'
      end

      unless %w(invisible damping reflecting absorbing2011 absorbing2007 default).include?(@analysis.problem['algorithm']['boundary'])
        raise 'unknown Boundary type'
      end

      unless %w(gbest lbest vonneumann random).include?(@analysis.problem['algorithm']['topology'])
        raise 'unknown Topology type'
      end

      if @analysis.problem['algorithm']['p_power'] <= 0
        raise 'P Norm must be non-negative'
      end

      @analysis.exit_on_guideline14 = @analysis.problem['algorithm']['exit_on_guideline14'] == 1 ? true : false

      @analysis.problem['algorithm']['objective_functions'] = [] unless @analysis.problem['algorithm']['objective_functions']

      @analysis.save!
      logger.info("exit_on_guideline14: #{@analysis.exit_on_guideline14}")

      # check to make sure there are objective functions
      if @analysis.output_variables.count { |v| v['objective_function'] == true }.zero?
        raise 'No objective functions defined'
      end

      # find the total number of objective functions
      if @analysis.output_variables.count { |v| v['objective_function'] == true } != @analysis.problem['algorithm']['objective_functions'].size
        raise 'Number of objective functions must equal between the output_variables and the problem definition'
      end

      pivot_array = Variable.pivot_array(@analysis.id, @r)
      logger.info "pivot_array: #{pivot_array}"
      selected_variables = Variable.variables(@analysis.id)
      logger.info "Found #{selected_variables.count} variables to perturb"

      # discretize the variables using the LHS sampling method
      @r.converse("print('starting lhs to discretize the variables')")
      logger.info 'starting lhs to discretize the variables'

      lhs = AnalysisLibrary::R::Lhs.new(@r)
      samples, var_types, mins_maxes, var_names = lhs.sample_all_variables(selected_variables, 3)

      # Result of the parameter space will be column vectors of each variable
      logger.info "Samples are #{samples}"
      logger.info "mins_maxes: #{mins_maxes}"
      logger.info "var_names: #{var_names}"
      logger.info("variable types are #{var_types}")
      if var_names.empty? || var_names.empty?
        logger.info 'No variables were passed into the options, therefore exit'
        raise "Must have at least one variable to run algorithm.  Found #{var_names.size} variables"
      end

      unless var_types.all? { |t| t.casecmp('continuous').zero? }
        logger.info 'Must have all continous variables to run algorithm, therefore exit'
        raise "Must have all continous variables to run algorithm.  Found #{var_types}"
      end

      # Start up the cluster and perform the analysis
      cluster = AnalysisLibrary::R::Cluster.new(@r, @analysis.id)
      unless cluster.configure
        raise 'could not configure R cluster'
      end

      worker_ips = {}
      if @analysis.problem['algorithm']['max_queued_jobs'] == 0
        raise 'MAX_QUEUED_JOBS is 0'
      elsif @analysis.problem['algorithm']['max_queued_jobs'] > 0
        worker_ips[:worker_ips] = ['localhost'] * @analysis.problem['algorithm']['max_queued_jobs']
        logger.info "Starting R queue to hold #{@analysis.problem['algorithm']['max_queued_jobs']} jobs"    
      elsif !APP_CONFIG['max_queued_jobs'].nil?
        worker_ips[:worker_ips] = ['localhost'] * APP_CONFIG['max_queued_jobs']
        logger.info "Starting R queue to hold #{APP_CONFIG['max_queued_jobs']} jobs"
      else
        raise 'could not start the cluster (cluster size not set correctly)'
      end
      if cluster.start(worker_ips)
        logger.info "Cluster Started flag is #{cluster.started}"
        # maxit is the max number of iterations to calculate

        # convert to float because the value is normally an integer and rserve/rserve-simpler only handles maxint
        @analysis.problem['algorithm']['failed_f_value'] = @analysis.problem['algorithm']['failed_f_value'].to_f
        @analysis.problem['algorithm']['abstol'] = @analysis.problem['algorithm']['abstol'].to_f
        @analysis.problem['algorithm']['reltol'] = @analysis.problem['algorithm']['reltol'].to_f
        @r.command(master_ips: master_ip, 
                   ips: worker_ips[:worker_ips].uniq, 
                   vartypes: var_types, 
                   varnames: var_names,
                   varseps: mins_maxes[:eps], 
                   mins: mins_maxes[:min], 
                   maxes: mins_maxes[:max],
                   normtype: @analysis.problem['algorithm']['norm_type'], 
                   ppower: @analysis.problem['algorithm']['p_power'],
                   objfun: @analysis.problem['algorithm']['objective_functions'],
                   npart: @analysis.problem['algorithm']['npart'],
                   maxfn: @analysis.problem['algorithm']['maxfn'],
                   abstol: @analysis.problem['algorithm']['abstol'],
                   reltol: @analysis.problem['algorithm']['reltol'],
                   maxit: @analysis.problem['algorithm']['maxit'],
                   c1: @analysis.problem['algorithm']['c1'],
                   c2: @analysis.problem['algorithm']['c2'],
                   lambda: @analysis.problem['algorithm']['lambda'],
                   xini: @analysis.problem['algorithm']['xini'],
                   vini: @analysis.problem['algorithm']['vini'],
                   boundary: @analysis.problem['algorithm']['boundary'],
                   topology: @analysis.problem['algorithm']['topology'],
                   debug_messages: @analysis.problem['algorithm']['debug_messages'],
                   failed_f: @analysis.problem['algorithm']['failed_f_value'],
                   method: @analysis.problem['algorithm']['method']) do
          %{
            rails_analysis_id = "#{@analysis.id}"
            rails_sim_root_path = "#{APP_CONFIG['sim_root_path']}"
            rails_ruby_bin_dir = "#{APP_CONFIG['ruby_bin_dir']}"
            rails_mongodb_name = "#{AnalysisLibrary::Core.database_name}"
            rails_mongodb_ip = "#{master_ip}"
            rails_run_filename = "#{@options[:run_data_point_filename]}"
            rails_create_dp_filename = "#{@options[:create_data_point_filename]}"
            rails_root_path = "#{Rails.root}"
            rails_host = "#{APP_CONFIG['os_server_host_url']}"
            r_scripts_path = "#{APP_CONFIG['r_scripts_path']}"
            rails_exit_guideline_14 = "#{@analysis.exit_on_guideline14}"
            source(paste(r_scripts_path,'/pso.R',sep=''))
          }
        end

        # TODO: find any results of the algorithm and save to the analysis
      else
        raise 'could not start the cluster (most likely timed out)'
      end

    rescue => e
      log_message = "#{__FILE__} failed with #{e.message}, #{e.backtrace.join("\n")}"
      logger.error log_message
      @analysis.status_message = log_message
      @analysis.save!
      @analysis_job.status = 'completed'
      @analysis_job.save!
      @analysis.reload
      @analysis.save!
    ensure
      # ensure that the cluster is stopped
      cluster.stop if cluster

      # Post process the results and jam into the database
      best_result_json = "#{APP_CONFIG['sim_root_path']}/analysis_#{@analysis.id}/best_result.json"
      if File.exist? best_result_json
        begin
          logger.info('read best result json')
          temp2 = File.read(best_result_json)
          temp = JSON.parse(temp2, symbolize_names: true)
          logger.info("temp: #{temp}")
          @analysis.results[@options[:analysis_type]]['best_result'] = temp
          @analysis.save!
          logger.info("analysis: #{@analysis.results}")
        rescue => e
          logger.error 'Could not save post processed results for bestresult.json into the database'
        end
      end

      # Post process the results and jam into the database
      converge_flag_json = "#{APP_CONFIG['sim_root_path']}/analysis_#{@analysis.id}/convergence_flag.json"
      if File.exist? converge_flag_json
        begin
          logger.info('read converge_flag.json')
          temp2 = File.read(converge_flag_json)
          temp = JSON.parse(temp2, symbolize_names: true)
          logger.info("temp: #{temp}")
          @analysis.results[@options[:analysis_type]]['convergence_flag'] = temp
          @analysis.save!
          logger.info("analysis: #{@analysis.results}")
        rescue => e
          logger.error 'Could not save post processed results for converge_flag.json into the database'
        end
      end

      # Only set this data if the analysis was NOT called from another analysis
      unless @options[:skip_init]
        @analysis_job.end_time = Time.now
        @analysis_job.status = 'completed'
        @analysis_job.save!
        @analysis.reload
      end
      @analysis.save!

      logger.info "Finished running analysis '#{self.class.name}'"
    end
  end
end
