define (require) ->
  $ = require 'jquery'
  marionette = require 'marionette'
  require 'bootstrap'
  THREE = require 'three'
  combo_cam = require 'combo_cam'
  detector = require 'detector'
  stats = require  'stats'
  utils = require 'utils'
  
  reqRes = require 'modules/core/reqRes'
  vent = require 'modules/core/vent'
  
  threedView_template = require "text!./visualEditorView.tmpl"
  requestAnimationFrame = require 'modules/core/utils/anim'
  orbit_ctrl = require 'orbit_ctrl'
  THREE.CSG = require 'modules/core/projects/csg/csg.Three'
  
  helpers = require './helpers'
  

  class VisualEditorView extends Backbone.Marionette.ItemView
    template: threedView_template
    ui:
      renderBlock :   "#glArea"
      glOverlayBlock: "#glOverlay" 
      overlayDiv:     "#overlay" 
      
    events:
      'contextmenu' : 'rightclick'
      
    constructor:(options, settings)->
      super options
      @vent = vent 
      @settings = options.settings
        
      @stats = new stats()
      @stats.domElement.style.position = 'absolute'
      @stats.domElement.style.top = '30px'
      @stats.domElement.style.zIndex = 100
      
      @settings.on( "change", @settingsChanged)
      @model.on("compiled", @projectCompiled)
      
      #screenshoting
      reqRes.addHandler "project:getScreenshot", ()=>
        return @makeScreeshot()
      
      ##########
      @width = 800
      @height = 600
      @init()
      
    makeScreeshot:(width=300, height=300)=>
      # Save screenshot of 3d view
      #resizing
      srcImg = @renderer.domElement.toDataURL("image/png")
      canvas = document.createElement("canvas")
      canvas.width = width
      canvas.height = height
      ctx = canvas.getContext('2d')
      #ctx.fillStyle = "red"
      #ctx.fillRect(0, 0, canvas.width, canvas.height)
      d = $.Deferred()
      imgAsDataURL =null 
      img = new Image()
      img.onload = ()=> 
        ctx.drawImage(img, 0,0,width, height)
        imgAsDataURL = canvas.toDataURL("image/png")
        d.resolve(imgAsDataURL)
      img.src = srcImg
      return d
    
    rightclick:(ev)=>
      """used either for selection or context menu"""
      normalizeEvent(ev)
      x = ev.offsetX
      y = ev.offsetY
      @selectObj(x,y)
      #context-menu
      # = require "modules/core/utils/contextMenu"
      #@contextMenu = new ContextMenu()
      #@contextMenu.show()
      
      #Contextmenu
      ###
      {ContextMenuRegion,ContextMenu} = require "views/contextMenuView"
      @contextMenu = new ContextMenu()
      @contextMenuRegion.show @contextMenu
      ###
      ev.preventDefault()
      return false
             
    selectObj:(mouseX,mouseY)=>
      v = new THREE.Vector3((mouseX/@width)*2-1, -(mouseY/@height)*2+1, 0.5)
      @projector.unprojectVector(v, @camera)
      ray = new THREE.Ray(@camera.position, v.subSelf(@camera.position).normalize())
      intersects=ray.intersectObjects(@scene.children, true )
      
      unselect=()=>
        if @current?
          @current.selected=false
          @current.material = @current.origMaterial
          if @current.cage?
            @current.remove @current.cage
            @current.cage = null
          @current=null
      
      if @current?
        unselect()
      if intersects? 
        if intersects.length > 0
          if intersects[0].object.name != "workplane"
              @current = intersects[0].object
              newMat = new  THREE.MeshLambertMaterial
                color: 0xCC0000
              @current.origMaterial = @current.material
              @current.material = newMat
              @addCage @current
      @_render()
    
    switchModel:(newModel)->
      #replace current model with a new one
      #@unbindAll()
      @scene.remove(@mesh)
      
      try
        @scene.remove @current.cageView
        @current=null
      
      @model = newModel
      @model.on("compiled", @projectCompiled)
      @fromCsg @model
      
    projectCompiled:(res)=>
      @fromCsg res
              
    settingsChanged:(settings, value)=> 
      for key, val of @settings.changedAttributes()
        switch key
          when "bgColor"
            @setBgColor()
          when "bgColor2"
            @setBgColor()
          when "renderer"
            delete @renderer
            @init()
            @fromCsg @model
            @render()
          when "showGrid"
            if val
              @addGrid()
            else
              @removeGrid()
          when "gridSize"
            if @grid?
              @removeGrid()
              @addGrid()
          when "gridStep"
            if @grid?
              @removeGrid()
              @addGrid()
          when "gridColor"
            if @grid?
              @grid.setColor(val)
          when "gridOpacity"
            if @grid?
              @grid.setOpacity(val)
          when "showAxes"
            if val
              @addAxes()
            else
              @removeAxes()
          when "shadows"
            if not val
              @renderer.clearTarget(@light.shadowMap)
              @fromCsg @model
              @render()
              @renderer.shadowMapAutoUpdate = false
              if @settings.get("showGrid")
                @removeGrid()
                @addGrid()
            else
              @renderer.shadowMapAutoUpdate = true
              @fromCsg @model
              @render()
              if @settings.get("showGrid")
                @removeGrid()
                @addGrid()
          when "selfShadows"
            @fromCsg @model
            @render()
          when "showStats"
            if val
              @ui.overlayDiv.append(@stats.domElement)
            else
              $(@stats.domElement).remove()
          when  "projection"
            if val == "orthographic"
              @camera.toOrthographic()
              #@camera.setZoom(6)
            else
              @camera.toPerspective()
              @camera.setZoom(1)
          when "position"
            @setupView(val)
          when "wireframe"
            #TODO: should not be global , but object specific?
            if @mesh?
              @mesh.material.wireframe = val
          when 'center'
            try
              tgt = @controls.target
              offset = new THREE.Vector3().subSelf(@controls.target.clone())
              @controls.target.addSelf(offset)
              @camera.position.addSelf(offset)
            catch error
              console.log "error #{error} in center"
            @camera.lookAt(@scene.position)
          when 'helpersColor'
            if @axes?
              @removeAxes()
              @addAxes()
          when 'textColor'
            if @axes?
              @removeAxes()
              @addAxes()
          when 'showConnectors'
            if val
              THREE.SceneUtils.traverseHierarchy @assembly, (object)-> 
                if object.name is "connectors"
                  object.visible = true 
            else
              THREE.SceneUtils.traverseHierarchy @assembly, (object)-> 
                if object.name is "connectors"
                  object.visible = false 
      @_render()  
       
    init:()=>
      @renderer=null
      #TODO: do this properly
      @configure(@settings)
      @renderer.shadowMapEnabled = true
      @renderer.shadowMapAutoUpdate = true
      
      @projector = new THREE.Projector()
      @setupScene()
      @setupOverlayScene()
      @setBgColor()
      
      if @settings.get("shadows")
        @renderer.shadowMapAutoUpdate = @settings.get("shadows")
      if @settings.get("showGrid")
        @addGrid()
      if @settings.get("showAxes")
        @addAxes()
      if @settings.get("projection") == "orthographic"
        @camera.toOrthographic()
        @camera.setZoom(6)
      else
        @camera.toPerspective()
      
      if @mesh?
        @mesh.material.wireframe = @settings.get("wireframe")
      
      
      val = @settings.get("position")
      @setupView(val)
        
    configure:(settings)=>
      if settings.get("renderer")
          renderer = settings.get("renderer")
          if renderer == "webgl"
            if detector.webgl
              console.log "Gl Renderer"
              @renderer = new THREE.WebGLRenderer 
                clearColor: 0x00000000
                clearAlpha: 0
                antialias: true
                preserveDrawingBuffer   : true
              @renderer.clear() 
              @renderer.setSize(@width, @height)
              
              @overlayRenderer = new THREE.WebGLRenderer 
                clearColor: 0x000000
                clearAlpha: 0
                antialias: true
              @overlayRenderer.setSize(350, 250)
            else if not detector.webgl and not detector.canvas
              #TODO: handle this correctly
              console.log("No Webgl and no canvas (fallback) support, cannot render")
            else if not detector.webgl and detector.canvas
              @renderer = new THREE.CanvasRenderer 
                clearColor: 0x00000000
                clearAlpha: 0
                antialias: true
              @renderer.clear() 
              @overlayRenderer = new THREE.CanvasRenderer 
                clearColor: 0x000000
                clearAlpha: 0
                antialias: true
              @overlayRenderer.setSize(350, 250)
              @renderer.setSize(@width, @height)
            else
              console.log("No Webgl and no canvas (fallback) support, cannot render")
          else if renderer =="canvas"
            if detector.canvas
              @renderer = new THREE.CanvasRenderer 
                clearColor: 0x00000000
                clearAlpha: 0
                antialias: true
              @renderer.clear() 
              @overlayRenderer = new THREE.CanvasRenderer 
                clearColor: 0x000000
                clearAlpha: 0
                antialias: true
              @overlayRenderer.setSize(350, 250)
              @renderer.setSize(@width, @height)
            else if not detector.canvas
              #TODO: handle this correctly
              console.log("No canvas support, cannot render")
    
    setupScene:()->
      @viewAngle=45
      ASPECT = @width / @height
      NEAR = 0.1
      FAR = 10000
      ### 
      @camera =
      new THREE.PerspectiveCamera(
          @viewAngle,
          ASPECT,
          NEAR,
          FAR)
      ###
      @camera =
       new THREE.CombinedCamera(
          @width,
          @height,
          @viewAngle,
          NEAR,
          FAR,
          NEAR,
          FAR)
      #function ( width, height, fov, near, far, orthoNear, orthoFar )
      
      @camera.up = new THREE.Vector3( 0, 0, 1 )
      
      @camera.position.x = 450
      @camera.position.y = 450
      @camera.position.z = 750
      
          
      @scene = new THREE.Scene()
      @scene.add(@camera)
      @setupLights()
      
      @cameraHelper = new THREE.CameraHelper(@camera)
      
    setupOverlayScene:()->
      #Experimental overlay
      ASPECT = 350 / 250
      NEAR = 1
      FAR = 10000
      @overlayCamera =
        #new THREE.PerspectiveCamera(@viewAngle,ASPECT, NEAR, FAR)
        new THREE.CombinedCamera(
          350,
          250,
          @viewAngle,
          NEAR,
          FAR,
          NEAR,
          FAR)
      @overlayCamera.up = new THREE.Vector3( 0, 0, 1 )
      
      #@overlayCamera.position.x = 150
      #@overlayCamera.position.y = 150
      #@overlayCamera.position.z = 250
      
      #@overlayCamera.toOrthographic()
      #@overlayCamera.setZoom(0.05)
      @overlayScene = new THREE.Scene()
      @overlayScene.add(@overlayCamera)

    setupLights:()=>
      pointLight =
        new THREE.PointLight(0x333333,3)
      pointLight.position.x = -2500
      pointLight.position.y = -2500
      pointLight.position.z = 2200
      
      pointLight2 =
        new THREE.PointLight(0x333333,3)
      pointLight2.position.x = 2500
      pointLight2.position.y = 2500
      pointLight2.position.z = -5200

      @ambientColor = '0x253565'
      @ambientColor = '0x354575'
      @ambientColor = '0x455585'
      @ambientColor = '0x565595'
      ambientLight = new THREE.AmbientLight(@ambientColor)
      
      spotLight = new THREE.SpotLight( 0xbbbbbb, 1.5)    
      spotLight.position.x = 0
      spotLight.position.y = 0
      spotLight.position.z = 4000
      spotLight.castShadow = true
      @light= spotLight 
      
      @scene.add(ambientLight)
      @scene.add(pointLight)
      @scene.add(pointLight2)
      @scene.add(spotLight)
      
      @camera.add(pointLight)
      
    setupView:(val)=>
      resetCam=()=>
        @camera.position.z = 0
        @camera.position.y = 0
        @camera.position.x = 0
      switch val
        when 'diagonal'
          @camera.position.x = -450
          @camera.position.y = -450
          @camera.position.z = 750
          
          @overlayCamera.position.x = -150
          @overlayCamera.position.y = -150
          @overlayCamera.position.z = 250
          
          @camera.lookAt(@scene.position)
          @overlayCamera.lookAt(@overlayScene.position)
          
        when 'top'
          #@camera.toTopView()
          #@overlayCamera.toTopView()
          
          try
            offset = @camera.position.clone().subSelf(@controls.target)
            nPost = new THREE.Vector3()
            nPost.z = offset.length()
            @camera.position = nPost
            
          catch error
            @camera.position = new THREE.Vector3(0,0,750)
            
          @overlayCamera.position = new THREE.Vector3(0,0,250)
          @camera.lookAt(@scene.position)
          @overlayCamera.lookAt(@overlayScene.position)
          #@camera.rotationAutoUpdate = true
          #@overlayCamera.rotationAutoUpdate = true
          
        when 'bottom'
          #@camera.toBottomView()
          #@overlayCamera.toBottomView()
          try
            offset = @camera.position.clone().subSelf(@controls.target)
            nPost = new  THREE.Vector3()
            nPost.z = -offset.length()
            @camera.position = nPost
          catch error
            @camera.position = new THREE.Vector3(0,0,-750)
            
          @overlayCamera.position = new THREE.Vector3(0,0,-250)
          @camera.lookAt(@scene.position)
          @overlayCamera.lookAt(@overlayScene.position)
          #@camera.rotationAutoUpdate = true
          
        when 'front'
          #@camera.toFrontView()
          #@overlayCamera.toFrontView()
          try
            offset = @camera.position.clone().subSelf(@controls.target)
            nPost = new  THREE.Vector3()
            nPost.y = -offset.length()
            @camera.position = nPost
          catch error
            @camera.position = new THREE.Vector3(0,-450,0)
            
          @overlayCamera.position = new THREE.Vector3(0,-250,0)
          @camera.lookAt(@scene.position)
          @overlayCamera.lookAt(@overlayScene.position)
          #@camera.rotationAutoUpdate = true
          
          
        when 'back'
          #@camera.toBackView()
          #@overlayCamera.toBackView()
          try
            offset = @camera.position.clone().subSelf(@controls.target)
            nPost = new  THREE.Vector3()
            nPost.y = offset.length()
            @camera.position = nPost
          catch error
            @camera.position = new THREE.Vector3(0,450,0)
          #@camera.rotationAutoUpdate = true
          @overlayCamera.position = new THREE.Vector3(0,250,0)
          @camera.lookAt(@scene.position)
          @overlayCamera.lookAt(@overlayScene.position)
          
        when 'left'
          #@camera.toLeftView()
          try
            offset = @camera.position.clone().subSelf(@controls.target)
            nPost = new  THREE.Vector3()
            nPost.x = offset.length()
            @camera.position = nPost
          catch error
            @camera.position = new THREE.Vector3(450,0,0)
          #@camera.rotationAutoUpdate = true
          @overlayCamera.position = new THREE.Vector3(250,0,0)
          @camera.lookAt(@scene.position)
          @overlayCamera.lookAt(@overlayScene.position)
          
        when 'right'
          #@camera.toRightView()
          try
            offset = @camera.position.clone().subSelf(@controls.target)
            nPost = new  THREE.Vector3()
            nPost.x = -offset.length()
            @camera.position = nPost
          catch error
            @camera.position = new THREE.Vector3(-450,0,0)
          #@camera.rotationAutoUpdate = true
          @overlayCamera.position = new THREE.Vector3(-250,0,0)
          @camera.lookAt(@scene.position)
          @overlayCamera.lookAt(@overlayScene.position)
         
      @_render()
     
    setBgColor:()=>
      console.log "setting bg color"
      bgColor1 = @settings.get("bgColor")
      bgColor2 = @settings.get("bgColor2")
      $("body").css("background-color", bgColor1)
      if bgColor1 != bgColor2
        $("body").css("background-image", "-moz-radial-gradient(center center, circle cover, #{bgColor1},#{bgColor2}  100%)")
        $("body").css("background-image", "-webkit-radial-gradient(center center, circle cover, #{bgColor1},#{bgColor2}  100%)")
        $("body").css("background-image", "-o-radial-gradient(center center, circle cover, #{bgColor1},#{bgColor2}  100%)")
        $("body").css("background-image", "-ms-radial-gradient(center center, circle cover, #{bgColor1},#{bgColor2}  100%)")
        $("body").css("background-image", "radial-gradient(center center, circle cover, #{bgColor1},#{bgColor2}  100%)")
        $("body").css("background-repeat", "no-repeat")
        $("body").css("background-attachment", "fixed")
      else
        $("body").css("background-image", "")
        $("body").css("background-image", "")
        $("body").css("background-repeat", "")
        $("body").css("background-attachment", "")
        
        #$("body").css('background-color', @settings.get("bkGndColor"))
        
    addGrid:()=>
      ###
      Adds both grid & plane (for shadow casting), based on the parameters from the settings object
      ###
      if not @grid 
        gridSize = @settings.get("gridSize")
        gridStep = @settings.get("gridStep")
        gridColor = @settings.get("gridColor")
        gridOpacity = @settings.get("gridOpacity")
        
        @grid = new helpers.Grid({size:gridSize,step:gridStep,color:gridColor,opacity:gridOpacity})
        @scene.add @grid
       
    removeGrid:()=>
      if @grid
        @scene.remove @grid
        delete @grid
      
    addAxes:()->
      helpersColor = @settings.get("helpersColor")
      @axes = new helpers.LabeledAxes({xColor:helpersColor, yColor:helpersColor, zColor:helpersColor, size:200, addLabels:false, addArrows:false})
      @scene.add(@axes)
      
      @overlayAxes = new helpers.LabeledAxes({textColor:@settings.get("textColor")})
      @overlayScene.add @overlayAxes
      
    removeAxes:()->
      @scene.remove @axes
      @overlayScene.remove @overlayAxes
      delete @axes
      delete @overlayAxes
      
    addCage:(mesh)=>
      new helpers.BoundingCage({mesh:mesh, color:@settings.get("helpersColor"),textColor:@settings.get("textColor")})
            
    setupPickerHelper:()->
      canvas = document.createElement('canvas')
      canvas.width = 100
      canvas.height = 100
      context = canvas.getContext('2d')
  
      PI2 = Math.PI * 2
      context.beginPath()
      context.arc( 0, 0, 1, 0, PI2, true )
      context.closePath()
      context.fill()
      context.fillText("X", 40, 40)

      texture = new THREE.Texture( canvas )
      texture.needsUpdate = true
      @particleTexture = new THREE.Texture(canvas)
      @particleTexture.needsUpdate = true
      @particleMaterial = new THREE.MeshBasicMaterial( { map: texture, transparent: true ,color: 0x000000} );
    
    onResize:()=>
      @width =  $("#glArea").width()
      @height = window.innerHeight-10
      #@camera.aspect = @width / @height
      #@camera.updateProjectionMatrix()
      
      @camera.setSize(@width,@height)
      @camera.updateProjectionMatrix()
      
      @renderer.setSize(@width, @height)
      
      #@overlayCamera.position.z = @camera.position.z/3
      #@overlayCamera.position.y = @camera.position.y/3
      #@overlayCamera.position.x = @camera.position.x/3
      
      @_render()
    
    onRender:()=>
      selectors = @ui.overlayDiv.children(" .uicons")
      #selectors.tooltip()
      
      if @settings.get("showStats")
        @ui.overlayDiv.append(@stats.domElement)
        
      @width = $("#visual").width()
      @height = window.innerHeight-10#$("#gl").height()
     
      #@camera.aspect = @width / @height
      #@camera.updateProjectionMatrix()
      @camera.setSize(@width,@height)
      @camera.updateProjectionMatrix()
      @renderer.setSize(@width, @height)
      
      #FIXME: remove this totally random stuff
      #@overlayCamera.position.z = @camera.position.z
      #@overlayCamera.position.y = @camera.position.y
      #@overlayCamera.position.x = @camera.position.x
      #@overlayCamera.position.z = 150
      #@overlayCamera.position.y = 250
      #@overlayCamera.position.x = 150
            
      @_render()
      
      
      @$el.resize @onResize
      window.addEventListener('resize', @onResize, false)
      ##########
      
      container = $(@ui.renderBlock)
      container.append(@renderer.domElement)
      @controls = new THREE.CustomOrbitControls(@camera, @el)
      @controls.rotateSpeed = 1.8
      @controls.zoomSpeed = 4.2
      @controls.panSpeed = 1.8
      
      #CustomOrbitControls
      #OrbitControls
      ###TrackballControls
      @controls.autoRotate = false
      @controls.noZoom = false
      @controls.noPan = false

      @controls.staticMoving = true
      @controls.dynamicDampingFactor = 0.3
      ###
      @controls.addEventListener( 'change', @_render )
      
      ########
      container2 = $(@ui.glOverlayBlock)
      container2.append(@overlayRenderer.domElement)
      
      @overlayControls = new THREE.CustomOrbitControls(@overlayCamera, @el)
      @overlayControls.noPan = true
      #@overlayControls.noZoom = true
      @overlayControls.rotateSpeed = 1.8
      @overlayControls.zoomSpeed = 0
      @overlayControls.panSpeed = 0
      @overlayControls.userZoomSpeed=0
      ### 
      @overlayControls.autoRotate = false
      @overlayControls.staticMoving = true
      @overlayControls.dynamicDampingFactor = 0.3
      ###
      @animate()
      
    
    _render:()=>
      @renderer.render(@scene, @camera)
      @overlayRenderer.render(@overlayScene, @overlayCamera)
      
      if @settings.get("showStats")
        @stats.update()
      #@cameraHelper.update()
      
    animate:()=>
      @controls.update()
      @overlayControls.update()

      requestAnimationFrame(@animate)
    
    toCsgTest:(mesh)->
      csgResult = THREE.CSG.toCSG(mesh)
      if csgResult?
        console.log "CSG conversion result ok:"
      
    fromCsg:(csg)=>
      #try
      start = new Date().getTime()
      res = csg
      #console.log "project compiled, updating view"
      if @assembly?
        @scene.remove @assembly
        @current=null
      
      @assembly = new THREE.Mesh(new THREE.Geometry())
      @assembly.name = "assembly"
      
      for index, part of res.children
        @_importGeom(part,@assembly)
        
      @scene.add @assembly 
      #catch error
      #  console.log "Csg Generation error: #{error} "
      #  @vent.trigger("csgParseError", error)
      #finally
      end = new Date().getTime()
      console.log "Csg visualization time: #{end-start}"
      @_render()
      
    _importGeom:(csgObj,rootObj)=>
      geom = THREE.CSG.fromCSG(csgObj)
      shine= 1500
      spec= 10000000000
      if @renderer instanceof THREE.CanvasRenderer
        mat = new THREE.MeshLambertMaterial({color:  0xFFFFFF}) 
        mat.overdraw = true
      else 
        mat = new THREE.MeshPhongMaterial({color:  0xFFFFFF , shading: THREE.SmoothShading,  shininess: shine, specular: spec, metal: true, vertexColors: THREE.VertexColors}) 
      mesh = new THREE.Mesh(geom, mat)
      mesh.castShadow =  @settings.get("shadows")
      mesh.receiveShadow = @settings.get("selfShadows") and @settings.get("shadows")
      mesh.material.wireframe = @settings.get("wireframe")
      mesh.name = csgObj.constructor.name
      
      if @renderer instanceof THREE.CanvasRenderer
        mesh.doubleSided = true
      
      #get object connectors
      for i, conn of geom.connectors
        ###
        mat =  new THREE.LineBasicMaterial({color: 0xff0000})
        line = new THREE.Line(conn, mat)
        @mesh.add line
        ###
        mat =  new THREE.MeshLambertMaterial({color: 0xff0000})
        connectorMesh = new THREE.Mesh(conn, mat)
        connectorMesh.name = "connectors"
        connectorMesh.position = conn.basePoint
        if @settings.get('showConnectors') == false
          connectorMesh.visible = false
        mesh.add connectorMesh   
       
      rootObj.add mesh
      #recursive, for sub objects
      if csgObj.children?
        for index, child of csgObj.children
          @_importGeom(child, mesh)
      

  return VisualEditorView
