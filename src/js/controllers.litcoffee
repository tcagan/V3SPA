    vespaControllers = angular.module('vespaControllers', 
        ['ui.ace', 'vespa.services', 'ui.bootstrap', 'ui.select2',
        'angularFileUpload', 'vespa.directives'])

The main controller. avispa is a subcontroller.

    vespaControllers.controller 'ideCtrl', ($scope, $rootScope, SockJSService, VespaLogger, $modal, AsyncFileReader, IDEBackend, $timeout, RefPolicy) ->

      $scope._ = _

      $scope.view_control = 
        unused_ports: false

      $scope.$watchCollection 'view_control', (new_collection)->
        for k, v of new_collection
          do (k, v)->
            IDEBackend.set_view_control k, v

      $scope.$watchCollection 'analysis_ctrl', (new_collection)->
        for k, v of new_collection
          do (k, v)->
            IDEBackend.set_query_param k, v

      $scope.policy = IDEBackend.current_policy

      $scope.blank_session = new ace.EditSession "", "ace/mode/text"

      IDEBackend.add_hook 'policy_load', (info)->
          $scope.policy = IDEBackend.current_policy

          $scope.editorSessions = {}
          for nm, doc of $scope.policy.documents
            do (nm, doc)->
              mode = if doc.mode then doc.mode else 'text'
              session = new ace.EditSession doc.text, "ace/mode/#{mode}"

              session.on 'change', (text)->
                IDEBackend.update_document nm, session.getValue(), 

              session.selection.on 'changeSelection', (e, sel)->
                IDEBackend.highlight_selection nm, sel.getRange()

              $scope.editorSessions[nm] = 
                session: session
                folded: true

              onfold = (session)->
                return (e)->
                  session.folded = false

              session.on('changeFold', onfold($scope.editorSessions[nm]))

          # There is no editor tab anymore
          #$scope.setEditorTab($scope.view)

      $timeout ->
        $scope.view = 'module_browser'

This controls our editor visibility.

      $scope.resizeEditor = (direction)->
        switch direction
          when 'larger'
            $scope.editorSize += 1 if $scope.editorSize < 2
          when 'smaller'
            $scope.editorSize -= 1

      $scope.editorSize = 1

      $scope.aceLoaded = (editor) ->
        editor.setTheme("ace/theme/solarized_light");
        editor.setKeyboardHandler("vim");
        editor.setBehavioursEnabled(true);
        editor.setSelectionStyle('line');
        editor.setHighlightActiveLine(true);
        editor.setShowInvisibles(false);
        editor.setDisplayIndentGuides(false);
        editor.renderer.setHScrollBarAlwaysVisible(false);
        editor.setAnimatedScroll(false);
        editor.renderer.setShowGutter(true);
        editor.renderer.setShowPrintMargin(false);
        editor.setHighlightSelectedWord(true);

        $scope.editor = editor
        editor.setSession $scope.blank_session
        editor.setOptions
          readOnly: true
          highlightActiveLine: false
          highlightGutterLine: false

        $scope.editorSessions = {}
        for nm, doc of $scope.policy.documents
          do (nm, doc)->
            mode = if doc.mode then doc.mode else 'text'
            session = new ace.EditSession doc.text, "ace/mode/#{mode}"

            session.on 'change', (text)->
              IDEBackend.update_document nm, session.getValue()

            $scope.editorSessions[nm] = 
              session: session

        IDEBackend.add_hook 'on_close', ->
          $scope.editor.setSession $scope.blank_session
          $scope.editor.setOptions
              readOnly: true
              highlightActiveLine: false
              highlightGutterLine: false

          for k of $scope.editorSessions
            delete $scope.editorSessions[k]

          $scope.editorSessions = {}

        IDEBackend.add_hook 'doc_changed', (doc, contents)->
            console.log "Document #{doc} changed event"
            $timeout ->
                $scope.editorSessions[doc].session.setValue contents
                do_fold = ->
                  if $scope.editorSessions[doc].folded == true
                    console.log "Folding", doc
                    $scope.editorSessions[doc].session.foldAll()


                # For some confounded r
                $timeout do_fold, 400


        $scope.editor_markers = []

Add all the highlights/annotations from the old session to the new DSL session.

        IDEBackend.add_hook 'validation', (annotations)->
          dsl_session = $scope.editorSessions.dsl.session

          format_error = (err)->
            pos = err.srcloc
            unless pos.start?
              lastRow = dsl_session.getLength()
              while _.isEmpty(toks = dsl_session.getTokens(lastRow))
                lastRow--

              pos = 
                start:
                  line: lastRow + 1
                  col: 1
                end:
                  line: lastRow + 1
                  col: dsl_session.getLine(lastRow).length + 1

            annotations.highlights ?= []
            annotations.highlights.push 
              range:  pos
              apply_to: 'dsl'
              type: 'error'

            ret = 
              row: pos.start.line
              column: pos.start.col
              type: 'error'
              text: "#{err.filename}: #{err.message}"

          $timeout ->
            session = $scope.editorSessions.dsl.session
            formatted_annotations = _.map(annotations?.errors, (e)->
              format_error(e)
            )                       
            session.setAnnotations formatted_annotations

          ace_range = ace.require("ace/range")

          $scope.editor_markers = _.filter $scope.editor_markers, (elem)->
            $scope.editor.getSession().removeMarker(elem)
            return false

          $timeout ->
            # highlight for e in annotations.highlighter
            _.each annotations.highlights, (hl)->
              return unless hl?

              range = new ace_range.Range(
                hl.range.start.line - 1,
                hl.range.start.col - 1,
                hl.range.end.line - 1,
                hl.range.end.col - 1
              )

              session_data = $scope.editorSessions[hl.apply_to]

              if not session_data.session?  # Just bail
                return

              session_data.session.unfold(range, false) # VSPA-86

              marker = session_data.session.addMarker(
                range,
                "#{hl.type}_marker",
                "text"
              )

              $scope.editor.scrollToLine hl.range.start.line - 10

              $scope.editor_markers.push marker

Watch the view control and switch the editor session

        $scope.setEditorTab = (name)->
          $timeout ->
            sessInfo = $scope.editorSessions[name]
            unless sessInfo
              return

            if sessInfo.tab? and not _.isEmpty sessInfo.tab
              prevIndex = sessInfo.tab.css('z-index')

            idx = 0
            for nm, info of $scope.editorSessions
              idx++
              if not info.tab? or _.isEmpty info.tab
                info.tab = angular.element "#editor_tabs \#tab_#{nm}"

              if nm == name
                info.tab.css 'z-index', 4
              else
                if prevIndex?
                  nowindex = info.tab.css('z-index')
                  if nowindex > prevIndex
                    info.tab.css 'z-index', nowindex - 1
                else
                  info.tab.css 'z-index', _.size($scope.editorSessions) - idx


            editor.setSession(sessInfo.session)

            if $scope.policy.documents[name].editable == false
              editor.setOptions
                readOnly: true
                highlightActiveLine: false
                highlightGutterLine: false
              editor.renderer.$cursorLayer.element.style.opacity=0
            else
              editor.setOptions
                readOnly: false
                highlightActiveLine: true
                highlightGutterLine: true
              editor.renderer.$cursorLayer.element.style.opacity=1

Ace needs a statically sized div to initialize, but we want it
to be the full page, so make it so.

        editor.resize()

Save the current file

      $scope.save_policy = ->
        IDEBackend.save_policy()

This function makes sure that a Reference Policy
has been loaded before calling the function
`open_modal`. It does so by opening the
reference policy load modal first if it has
not been loaded.

      ensure_refpolicy = (open_modal)->
        if RefPolicy.loading?
          RefPolicy.loading.then (policy)->
            open_modal(policy)

        else if RefPolicy.current?
          open_modal(RefPolicy.current)

        else
          # Load a reference policy
          instance = $modal.open
              templateUrl: 'refpolicyModal.html'
              controller: 'modal.refpolicy'

          instance.result.then (promise)->
              if promise
                  promise.then (refpol)->
                    if refpol
                      # When the refpolicy has actually been loaded,
                      # open the upload modal.
                      open_modal(refpol)

Create a modal for opening a policy

      $scope.open_policy = ->

        ensure_refpolicy (refpol)->
          IDEBackend.load_local_policy refpol

        #instance = $modal.open
        #  templateUrl: 'policyOpenModal.html'
        #  controller:  'modal.policy_open'

Modal dialog for new policy

      $scope.new_policy = ->
        ensure_refpolicy ->
          instance = $modal.open
            templateUrl: 'policyNewModal.html'
            controller: ($scope, $modalInstance)->

              $scope.policy = 
                type: 'selinux'

              $scope.load = ->
                $modalInstance.close($scope.policy)

              $scope.cancel = $modalInstance.dismiss

          instance.result.then (policy)->
              IDEBackend.new_policy
                id: policy.name
                type: policy.type
                refpolicy_id: RefPolicy.current._id


Create a modal for uploading policies. First we check if a reference policy
is loaded. If it is, then we open the upload modal. Otherwise we open the
RefpolicyLoad modal first, then open the file upload modal.

      $scope.upload_policy = ->

First we define the load modal function so we can call it conditionally later

        ensure_refpolicy ->

          instance = $modal.open
            templateUrl: 'policyLoadModal.html'
            controller: 'modal.policy_load'

If we get given files, read them as text and send them over the websocket

          instance.result.then(
            (inputs)-> 
              console.log(inputs)

              filelist = inputs.files

              AsyncFileReader.read filelist, (files)->
                req = 
                  domain: 'policy'
                  request: 'create'
                  payload: 
                    refpolicy_id: RefPolicy.current._id
                    documents: {}
                    type: 'selinux'

                for file, text of files
                  do (file, text)->
                    req.payload.documents[file] = 
                      text: text
                      editable: false

                SockJSService.send req, (result)->
                  if result.error
                    $.growl {title: 'Failed to upload module', message: result.payload}, 
                      type: 'danger'
                    console.log result
                  else
                    $.growl {title: 'Uploaded new module', message: result.payload.id}, 
                      type: 'success'

            ()->
              console.log("Modal dismissed")
          )


The console controller is very simple. It simply binds it's errors
scope to the VespaLogger scope

    vespaControllers.controller 'consoleCtrl', ($scope, VespaLogger) ->

      $scope.errors = VespaLogger.messages

      $scope.errorClass = (error, prepend)->
        switch error.level
          when 'error' then return "#{prepend}danger"
          when 'info' then return "#{prepend}default"
          when 'warning' then return "#{prepend}warning"
