# Notebook revision model
class Revision < ActiveRecord::Base
  belongs_to :notebook
  belongs_to :user

  include ExtendableModel

  class << self
    # Create a Revision from a Notebook object
    def from_notebook(notebook, revtype, commit_id, user=nil)
      rev = Revision.new(
        notebook: notebook,
        public: notebook.public,
        user: user,
        revtype: revtype,
        commit_id: commit_id
      )
      # If there are visibility-related extension attributes, we want those
      # copied across so we can do visibility permission checking on revisions.
      Notebook.extension_attributes.each do |attr|
        setter = "#{attr}=".to_sym
        rev.send(setter, notebook.send(attr.to_sym)) if rev.respond_to?(setter)
      end
      rev
    end

    # Create initial revisions for all existing notebooks
    def init
      commit_id = GitRepo.init
      Notebook.find_in_batches(batch_size: 100) do |batch|
        revisions = batch.map {|nb| Revision.from_notebook(nb, 'initial', commit_id)}
        Revision.import(revisions, validate: false)
      end
    end

    # Helper for recording a notebook revision
    def notebook_commit(revtype, notebook, user, message)
      commit_id = GitRepo.add_and_commit(notebook, message)
      rev = Revision.from_notebook(notebook, revtype, commit_id, user)
      rev.save
      commit_id
    end

    # Create a revision for a new notebook
    def notebook_create(notebook, user, message)
      notebook_commit('create', notebook, user, message)
    end

    # Create a revision for an updated notebook
    def notebook_update(notebook, user, message)
      notebook_commit('update', notebook, user, message)
    end

    # Create a revision for a deleted notebook
    def notebook_delete(notebook, _user, message)
      # On delete, we update git, but we don't create a Revision object
      # since the notebook is no longer in the database.
      GitRepo.add_and_commit(notebook, message, true)
    end

    # Create a revision for a (permissions-related) metadata change
    def notebook_metadata(notebook, user, _message=nil)
      # Metadata changes are reflected in the database but not git.
      # Currently this is only used for visibility changes (public/private).
      # Insert the previous commit_id so we can still grab content from git.
      commit_id = notebook.revisions.last.commit_id
      rev = Revision.from_notebook(notebook, 'metadata', commit_id, user)
      rev.save
      commit_id
    end

    # Custom permissions for revision read
    def custom_permissions_read(_notebook, _user, _use_admin=false)
      true
    end
  end

  # Helper for custom read permisssions
  def custom_read_check(user, use_admin=false)
    Revision.custom_permissions_read(self, user, use_admin)
  end

  # Get content of this revision
  def content
    GitRepo.content(notebook, commit_id)
  end

  # Use commit id in URLs
  def to_param
    commit_id
  end
end
