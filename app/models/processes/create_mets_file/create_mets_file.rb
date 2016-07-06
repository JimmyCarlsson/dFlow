#require_relative 'sources/dublin_core'
#require_relative 'sources/libris'
#require_relative 'sources/manuscript'
require 'yaml'

class CreateMetsFile

  def self.run(job:, logger: QueueManager.logger, 
               job_folder_path:, 
               mets_file_path:, 
               formats_required:, 
               files_required:,
               creator_name:, 
               creator_sigel:, 
               archivist_name: nil, 
               archivist_sigel: nil, 
               copyright_true_text: 'copyrighted', 
               copyright_false_text: 'pd', 
               require_physical: false, 
               validate_group_names: false
              )

    # Create arrays for formats and files
    formats_required = formats_required.split(",")
    files_required = files_required.split(",")
    
    # Set archivist values to creator values if not given
    archivist_name = creator_name if archivist_name.nil?
    archivist_sigel = creator_sigel if archivist_sigel.nil?

    copyright_text = copyright_true_text if job.copyright
    copyright_text = copyright_false_text if !job.copyright

    # Raise error if there is no page count info, needed to be able to validate package contents
    if job.page_count < 1
      raise StandardError, "Page count is needs to be a positive number, is: #{job.page_count}"
    end
 
    mets = MetsObject.new(job: job, logger: logger, job_folder_path: job_folder_path, mets_file_path: mets_file_path, copyright_text: copyright_text, creator_name: creator_name, creator_sigel: creator_sigel, archivist_name: archivist_name, archivist_sigel: archivist_sigel, formats_required: formats_required, files_required: files_required)
    mets.create_mets_xml_file
   
    #mets.move_metadata_folders
    #mets.move_mets_package
    #job.update_attributes(package_location: "STORE")
    
  end

  # Describing one file, used for handling locations, checksums, renaming
  class MetsFileObject
    attr_accessor :number, :checksum, :name
    def initialize(job_id:, path:, filename:, size:)
      @job_id = job_id
      @path = path
      @name = filename
      @size = size
      set_full_path
      @extension = filename.gsub(/^.*\.([^\.]+)$/,'\1')
      @number = filename.gsub(/^(\d+)\.[^\.]+$/,'\1')
      @checksum = DfileApi.checksum("PACKAGING", @full_path)
    end

    # Setting full path definition. Used both in initialize and renameing
    def set_full_path
      @full_path = "#{@job_id}/#{@path}/#{@name}"
    end

  end

  # Describing a file group containing multiple or single file(s)
  # Keeps track of file type (extension), directory name within job,
  # and whether or not there should be multiple or single file entries
  class MetsFileGroup
    attr_accessor :files, :name, :mimetype
    def initialize(job:, name:, mimetype:, extension:, single: false, folder_path:, file_path: nil)
      @job = job
      @job_id = job.id
      @name = name
      @mimetype = mimetype
      @extension = extension
      @single = single
      @files = []
      @folder_path = folder_path
      @file_path = file_path
      add_files
      count = @job.page_count
      if @single
        count = 1
      end
      # TODO: Raise exception if files do not correspond to jobs file count if single flag is false
      if @files.count != count
        raise StandardError, "Wrong number of files for #{@name}, wanted: #{count}, found: #{@files.count}"
      end
      
    end

    # Keep track of all relevant files in the directory
    def add_files
      DfileApi.list_files(source_dir: @folder_path, extension: @extension).each do |file|
        @files << MetsFileObject.new(job_id: @job_id, path: @name, filename: file['name'], size: file['size'])
      end
    end

    # Only a single file should be kept in this group
    def single?
      @single
    end
  end

  # Setup all necessary parts for creating METS XML
  class MetsObject

    def initialize(job:, 
                   logger: Logger.new("#{Rails.root}/log/create_mets_package.log"), 
                   job_folder_path:, 
                   mets_file_path:, 
                   copyright_text:, 
                   creator_name:, 
                   creator_sigel:, 
                   archivist_name:, 
                   archivist_sigel:,
                   formats_required:,
                   files_required:
                  )
      @job = job
      @logger = logger
      @copyright_text = copyright_text
      @creator_name = creator_name
      @creator_sigel = creator_sigel
      @archivist_name = archivist_name
      @archivist_sigel = archivist_sigel
      @job_folder_path = job_folder_path
      @mets_file_path = mets_file_path
      @formats_required = formats_required
      @files_required = files_required

      case @job.source
      when 'libris'
        @source = CreateMetsFile::Libris.new(@job, mets_data)
      when 'dc'
        @source = CreateMetsFile::DublinCore.new(@job, mets_data)
      when 'document'
        @source = CreateMetsFile::Manuscript.new(@job, mets_data, 'document')
      when 'letter'
        @source = CreateMetsFile::Manuscript.new(@job, mets_data, 'letter')
      end

      @file_groups = []
      @file_groups << MetsFileGroup.new(job: @job, name: "master",mimetype: "image/tiff",extension: "tif", folder_path: @job_folder_path + "/master") if @formats_required.include?('master')
      @file_groups << MetsFileGroup.new(job: @job, name: "web", mimetype: "image/jpeg", extension: "jpg", folder_path: @job_folder_path + "/web") if @formats_required.include?('web')
      @file_groups << MetsFileGroup.new(job: @job, name: "alto", mimetype: "text/xml", extension: "xml", folder_path: @job_folder_path + "/alto") if @formats_required.include?('alto')
      @file_groups << MetsFileGroup.new(job: @job, name: "pdf", mimetype: "text/pdf", extension: "pdf", single: true, folder_path: @job_folder_path + "/pdf", file_path: @files_required.first) if @files_required.first.present?
    end

    # Creates the mets xml file in package folder
    def create_mets_xml_file
      content = mets_xml
      if !xml_valid?(content)
        raise StandardError, "Invalid XML"
      end
      DfileApi.create_file(dest_file: @mets_file_path, content: mets_xml)
    end

    def xml_valid?(xml)
      test = Nokogiri::XML(xml)
      test.errors.empty?
    end

    # Collect global data used by METS production in various places
    def mets_data
      {
        id: @job.package_name,
        created_at: DateTime.parse(@job.created_at.to_s).strftime("%FT%T"),
        updated_at: DateTime.parse(@job.updated_at.to_s).strftime("%FT%T"),
        creator_sigel: @creator_sigel,
        creator_name: @creator_name,
        archivist_sigel: @archivist_sigel,
        archivist_name: @archivist_name,
        copyright_status: @copyright_text,
        publication_status: 'unpublished'
      }
    end

    # Build actual METS XML from all the pieces
    def mets_xml
      xml = head
      xml += extra_dmdsecs
      xml += bibliographic
      xml += administrative
      xml += filegroup_sections
      xml += structure_section_physical
      xml += structure_section_logical
      Nokogiri::XML(root(xml), &:noblanks).to_xml(encoding:'utf-8', indent: 2)
    end

    # Root element wrapper for METS XML
    ##
    # så sva det vara:
    #<mets:mets
    #xmlns:mets="http://www.loc.gov/METS/"
    #xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    #xmlns:rights="http://www.loc.gov/rights/"
    #xmlns:xlink="http://www.w3.org/1999/xlink"
    #xsi:schemaLocation="http://www.loc.gov/METS/ http://www.loc.gov/standards/mets/mets.xsd">
    #
    def root(xml)
      %Q(<mets:mets xmlns:mets="http://www.loc.gov/METS/"
       xmlns:xlink="http://www.w3.org/1999/xlink"
       xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
       xsi:schemaLocation="http://www.loc.gov/METS/ http://www.loc.gov/standards/mets/mets.xsd">#{xml}</mets:mets>)
    end

    # METS XML header information
    #  Creator and archivist
    def head
      %Q{<mets:metsHdr ID="#{mets_data[:id]}"
      CREATEDATE="#{mets_data[:created_at]}" LASTMODDATE="#{mets_data[:updated_at]}"
      RECORDSTATUS="complete">
      <mets:agent ROLE="CREATOR" TYPE="ORGANIZATION" ID="#{mets_data[:creator_sigel]}">
      <mets:name>#{mets_data[:creator_name]}</mets:name>
      </mets:agent>
      <mets:agent ROLE="ARCHIVIST" TYPE="ORGANIZATION" ID="#{mets_data[:archivist_sigel]}">
      <mets:name>#{mets_data[:archivist_name]}</mets:name>
      </mets:agent>
      </mets:metsHdr>}
    end

    # METS XML administrative information
    #  Copyright/publication status
    def administrative
      %Q(<mets:amdSec ID="amdSec1" >
        <mets:rightsMD ID="rightsDM1">
        <mets:mdWrap MDTYPE="OTHER">
        <mets:xmlData>
        <copyright copyright.status="#{mets_data[:copyright_status]}" publication.status="#{mets_data[:publication_status]}" xsi:noNamespaceSchemaLocation="http://www.cdlib.org/groups/rmg/docs/copyrightMD.xsd"/>
        </mets:xmlData>
        </mets:mdWrap>
        </mets:rightsMD>
        </mets:amdSec>)
    end

    # METS XML bibliographic information
    #  Translated (if necessary) output of source XML data
    #
    # Content handled by @source
    def bibliographic
      %Q(<mets:dmdSec ID="dmdSec1" CREATED="#{mets_data[:created_at]}">
        <mets:mdWrap MDTYPE="#{@source.xml_type}">
        <mets:xmlData>
      #{@source.xml_data}
        </mets:xmlData>
        </mets:mdWrap>
        </mets:dmdSec>)
    end

    # METS XML Special dmdSec:s for image data for manuscript sources
    #
    # Content handled by @source
    def extra_dmdsecs
      @source.extra_dmdsecs
    end

    # METS XML file section
    #  Single file entry with id, mimetype, path/name and checksum
    def file_section(file_group, file)
      %Q(<mets:file ID="#{file_group.name}#{file.number}"
        MIMETYPE="#{file_group.mimetype}"
        CHECKSUMTYPE="SHA-512"
        CHECKSUM="#{file.checksum}">
        <mets:FLocat LOCTYPE="URL" xlink:href="#{file_group.name}/#{file.name}" />
        </mets:file>)
    end

    # METS XML file group section
    #  Single file group entry collecting files
    def filegroup_section(file_group)
      file_data = file_group.files.map do |file|
        file_section(file_group, file)
      end
      %Q(<mets:fileGrp USE="#{file_group.name}">#{file_data.join("")}</mets:fileGrp>)
    end

    # METS XML file group sections
    #  Wrapper for all file group sections
    def filegroup_sections
      file_group_data = @file_groups.map do |file_group|
        filegroup_section(file_group)
      end
      %Q(<mets:fileSec ID="fileSec1">#{file_group_data.join("")}</mets:fileSec>)
    end

    # METS XML structure section for logical structure
    #  Single entry for one image, and its logical content information
    #  Titlepage/Image/Text
    def structure_image_logical(image)
      image_num = image['num'].to_i
      image_group = image['group_name']
      dmdid = @source.dmdid_attribute(image_group)

      image_filegroup_data = @file_groups.map do |file_group|
        next '' if file_group.single?
        "<mets:fptr FILEID=\"#{file_group.name}#{sprintf("%04d", image_num)}\"/>"
      end

      %Q(<mets:div TYPE="#{image['page_content']}"
       ID="logical_divpage#{image_num}"
       ORDER="#{image_num}"#{dmdid}>
      #{image_filegroup_data.join("")}
       </mets:div>)
    end

    # METS XML structure section for physical structure
    #  Single entry for one image, and its physical type information
    #  Right/Left/"Cover"/...
    def structure_image_physical(image)
      image_num = image['num'].to_i
      image_filegroup_data = @file_groups.map do |file_group|
        next '' if file_group.single?
        "<mets:fptr FILEID=\"#{file_group.name}#{sprintf("%04d", image_num)}\"/>"
      end

      %Q(<mets:div TYPE="#{image['page_type']}"
       ID="physical_divpage#{image_num}"
       ORDER="#{image_num}">
      #{image_filegroup_data.join("")}
       </mets:div>)
    end

    # METS XML structure for logical entries
    #  Wrapper for all logical structure entries
    def structure_section_logical
      structure_data = @job.package_metadata_hash['images'].map do |image|
        structure_image_logical(image)
      end

      %Q(<mets:structMap TYPE="Logical">
       <mets:div TYPE="#{@source.type_of_record}">
      #{structure_data.join('')}
       </mets:div>
       </mets:structMap>)
    end

    # METS XML structure for physical entries
    #  Wrapper for all physical structure entries
    def structure_section_physical
      #pp @job['package_metadata']
      structure_data = @job.package_metadata_hash['images'].map do |image|
        structure_image_physical(image)
      end

      %Q(<mets:structMap TYPE="Physical">
       <mets:div TYPE="#{@source.type_of_record}">
      #{structure_data.join('')}
       </mets:div>
       </mets:structMap>)
    end
  end
end
