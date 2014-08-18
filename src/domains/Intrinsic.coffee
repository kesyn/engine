# Functions are only called for primitive values
# When it encounters variables, it leaves expression to solver

# Provide some values for solver to crunch
# Simplifies expressions, caches DOM computations

# Measurements happen synchronously,
# re-measurements are deferred to be done in bulk

Numeric = require('./Numeric')
Native = require('../methods/Native')
debugger
class Intrinsic extends Numeric
  priority: 100
  structured: true
  
  Types:       require('../methods/Types')
  Units:       require('../methods/Units')
  Style:       require('../concepts/Style')

  Methods:     Native::mixin((new Numeric::Methods),
               require('../methods/Types'),
               require('../methods/Units'),
               require('../methods/Transformations'))

  Properties:  Native::mixin {},
               require('../properties/Dimensions'),
               require('../properties/Styles')

  constructor: ->
    @types = new @Types(@)
    @units = new @Units(@)

  getComputedStyle: (element, force) ->
    unless (old = element.currentStyle)?
      computed = (@computed ||= {})
      id = @identity.provide(element)
      old = computed[id]
      if force || !old?
        return computed[id] = window.getComputedStyle(element)
    return old

  restyle: (element, property, value = '') -> 
    element.style[property] = value

  get: (element, property) ->
    if !property
      path = element
      element = undefined
    else
      path = @getPath(element, property)
    if (j = path.indexOf('[')) > -1
      element ||= path.substring(0, j)
      property = path.substring(j + 1)
    else
      property = path

    if element && property && (prop = @properties[path])?
      if typeof prop == 'function'
        return prop.call(@, element)
      else
        return prop
    if !element.nodeType
      element = @identity.solve(element)
    if (index = property.indexOf('intrinsic-')) > -1
      if @properties[property]
        value = @properties[property].call(@, element)
      property = property.substring(index + 10, property.length - 1)

    prop = @camelize(property)
    value = element.style[property]
    if value == ''
      value = @getComputedStyle(element)[prop]
    if typeof value == 'string'
      if value.indexOf('px') > -1
        value = parseInt(value)
      else
        value = undefined
    if typeof value != 'number' && @properties.intrinsic[property]
      value = @properties.intrinsic[property].call(@, element)
    debugger
    @set null, path, value, undefined, false

    return value
    #value = @toPrimitive(value, null, null, null, element, prop)
    #if value.push && typeof value[0] == 'object'
    #  return @properties[property].apply(@, value)
    #else
    #  return @properties[property].call(@, value)

  # Triggered on possibly resized element by mutation observer
  # If an element is known to listen for its intrinsic properties
  # schedule a reflow on that element. If another element is already
  # scheduled for reflow, reflow shared parent element of both elements 
  validate: (node) ->
    return unless subscribers = @objects
    reflown = undefined
    while node
      if node == @scope
        if @engine.workflow.reflown
          reflown = @getCommonParent(reflown, @engine.workflow)
        else
          reflown = @scope
        break
      if node == @engine.workflow.reflown
        break 
      if id = node._gss_id
        if properties = subscribers[id]
          reflown = node
      node = node.parentNode
    @engine.workflow.reflown = reflown

  # Compute value of a property, reads the styles on elements
  verify: (node, property, continuation, old, returnPath, primitive) ->
    if node == window
      id = '::window'
    else if node.nodeType
      id = @identity.provide(node)
    else
      id = node
      node = @ids[id]

    path = @getPath(id, property)

    unless (value = @buffer?[path])?
      # property on specific element (e.g. ::window[height])
      if (prop = @properties[id]?[property])? 
        current = @values[path]
        if current == undefined || old == false
          switch typeof prop
            when 'function'
              value = prop.call(@, node, continuation)
            when 'string'
              path = prop
              value = @properties[prop].call(@, node, continuation)
            else
              value = prop
      # dom measurement
      else if intrinsic = @getIntrinsicProperty(property)
        if document.body.contains(node)
          if prop ||= @properties[property]
            value = prop.call(@, node, property, continuation)
          else
            value = @getStyle(node, intrinsic)
        else
          value = null
      #else if GSS.dummy.style.hasOwnProperty(property) || (property == 'x' || property == 'y')
      #  if @properties.intrinsic[property]
      #    val = @properties.intrinsic[property].call(@, node, continuation)
      #    console.error('precalc', node, property, value)
      #    (@computed ||= {})[path] = val
      else if @[property]
        value = @[property](node, continuation)
      else return
    if primitive
      return @values.set(id, property, value)
    else
      if value != undefined
        (@buffer ||= {})[path] = value
    return if returnPath then path else value

  # Decide common parent for all mutated nodes
  getCommonParent: (a, b) ->
    aps = []
    bps = []
    ap = a
    bp = b
    while ap && bp
      aps.push ap
      bps.push bp
      ap = ap.parentNode
      bp = bp.parentNode
      if bps.indexOf(ap) > -1
        return ap
      if aps.indexOf(bp) > -1
        return bp

    return suggestions


  # Iterate elements and measure intrinsic offsets
  each: (parent, callback, x,y, offsetParent, a,r,g,s) ->
    scope = @engine.scope
    parent ||= scope

    # Calculate new offsets for given element and styles
    if offsets = callback.call(@, parent, x, y, a,r,g,s)
      x += offsets.x || 0
      y += offsets.y || 0

    if parent.offsetParent == scope
      x -= scope.offsetLeft
      y -= scope.offsetTop
    else if parent != scope
      if !offsets 
        measure = true

    # Recurse to children
    if parent == document
      parent = document.body
    child = parent.firstChild
    index = 0
    while child
      if child.nodeType = 1
        if measure && index == 0 && child.offsetParent == parent
          x += parent.offsetLeft + parent.clientLeft
          y += parent.offsetTop + parent.clientTop
          offsetParent = parent
        @each(child, callback, x, y, offsetParent, a,r,g,s)
        index++

      child = child.nextSibling
    return a

  update: (node, x, y, full) ->
    return unless @objects
    if id = node._gss_id
      if properties = @objects[id]
        for prop of properties
          continue if full && (prop == 'width' || prop == 'height')
        
          switch prop
            when "x", "intrinsic-x"
              @set id, prop, x + node.offsetLeft
            when "y", "intrinsic-y"
              @set id, prop, y + node.offsetTop
            when "width", "intrinsic-width"
              @set id, prop, node.offsetWidth
            when "height", "intrinsic-height"
              @set id, prop, node.offsetHeight
            else
              @set id, prop, @getStyle(node, @engine.getIntrinsicProperty(prop))


  @condition: ->
    window?  
  url: null
module.exports = Intrinsic