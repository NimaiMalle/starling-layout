package viewLayout {

	import com.justin.validator.ExpressionEvaluator;
	import com.justin.validator.IEvalLookup;
	
	import flash.geom.Matrix;
	import flash.geom.Rectangle;
	import flash.utils.Dictionary;
	import flash.utils.getTimer;
	
	import animations.AnimationManager;
	import animations.ITargetResolver;
	
	import avmplus.getQualifiedClassName;
	
	import dataModel.IDataModel;
	
	import feathers.controls.Button;
	import feathers.controls.Label;
	import feathers.controls.PickerList;
	import feathers.controls.Slider;
	import feathers.controls.supportClasses.LayoutViewPort;
	import feathers.core.FeathersControl;
	import feathers.display.Scale3Image;
	import feathers.display.Scale9Image;
	import feathers.textures.Scale3Textures;
	import feathers.textures.Scale9Textures;
	
	import mediator.StatsController;
	
	import model.ConsoleModel;
	import model.ILayoutDataModel;
	
	import org.as3commons.reflect.Type;
	
	import processes.BaseProcessManager;
	import processes.ProcessManager;
	import processes.TimedCall;
	
	import resources.ResourceBundle;
	import resources.ResourceManager;
	import resources.resourceTypes.BitmapFontResource;
	import resources.resourceTypes.IResource;
	import resources.resourceTypes.TextureAtlasResource;
	import resources.resourceTypes.TextureResource;
	
	import service.ErrorManager;
	
	import signals.BaseSignal;
	import signals.CountedSignal;
	
	import starling.core.Starling;
	import starling.display.DisplayObject;
	import starling.display.DisplayObjectContainer;
	import starling.display.Image;
	import starling.display.Quad;
	import starling.display.Sprite;
	import starling.events.Event;
	import starling.text.BitmapFont;
	import starling.textures.Texture;
	import starling.textures.TextureAtlas;
	import starling.utils.MatrixUtil;
	
	import ui.controls.BCGTiledImage;
	import ui.controls.LayoutGroup;
	import ui.controls.LocLabel;
	
	import util.DebugUtils;
	import util.GraphicsUtil;
	import util.IEvaluator;
	import util.LayoutUtil;
	import util.Serialization;
	import util.SerializationStackEntry;
	import util.TTLCache;
	import util.UIFactory;
	import util.ViewportUtil;
	
	import view.BaseView;

	CONFIG::MOBILE {
		import signals.BaseSignal;
	}

		public class ViewLayout implements IEvalLookup, IEvaluator, ITargetResolver {

			public static var ACTIVE_VARIANTS:Array = [];	// Add the names of the active layout variants.  Must start with periods.
			protected static var _expressions:Dictionary = new Dictionary();

			protected var _viewFilename:String;
			protected var _resourceManager:ResourceManager;
			protected var _consoleModel:ConsoleModel;

			protected var _controlConfigs:Dictionary = new Dictionary();	// id => ConfigurableControl

			protected var _controls:Dictionary = new Dictionary(true);	// id => DisplayObject
			protected var _delayedControls:Dictionary = new Dictionary();	// id => config data
			protected var _delay:int = 0;

			protected var _controlGroups:Dictionary = new Dictionary();	// id => Vector.<DisplayObject>
			protected var _controlGroupIndexes:Dictionary = new Dictionary();	// DisplayObject => int

			protected var _layoutPhase:int = -1;
			protected var _removed:Boolean = false;
			protected var _simple:uint = 1;	// 0 = do full layout, 1 = do 2 passes in 1 frame, 2 = do 1 pass only
			protected var _rootControl:DisplayObject;
			protected var _controlList:Vector.<ConfigurableControl>;
			protected var _tempList:Vector.<ConfigurableControl>;
			protected var _dataModels:Dictionary = new Dictionary(); // id => IDataModel
			protected var _styles:Dictionary;	// id => style data object
			protected var _help:Vector.<Object>; //TODO: figure out best data structure for this (possibly an array)
			protected var _resourceBundles:Vector.<ResourceBundle> = new Vector.<ResourceBundle>();
			protected var _animationManager:AnimationManager = new AnimationManager();
			protected var _stats:StatsController;
			protected var _parent:DisplayObjectContainer;
			protected var _context:Dictionary;
			protected var _contextValues:Dictionary;
			protected var _contextTags:Vector.<String>;
			protected var _evaluator:ExpressionEvaluator = new ExpressionEvaluator();
			protected var _ser:Serialization;
			protected var _objectSerializer:Serialization;
			private var _currentControl:DisplayObject;
			public var viewResourcesLoadedSignal:CountedSignal = new CountedSignal();
			public var layoutCompleteSignal:CountedSignal = new CountedSignal();
			protected var childrenLayoutCompleteSignal:CountedSignal = new CountedSignal();
			private var _uniqueIdGroups:Dictionary;

			private var _childViews:Vector.<BaseView>;

			private var positionedControlCache:Dictionary = new Dictionary();
			private var positionedControlLookup:Dictionary = new Dictionary();

			public function get ser():Serialization { return _ser; }

			public var collectTexturesDeferrable:Boolean = true;

			private var _deferredTextureInfo:Vector.<DeferredTextureInfo> = new Vector.<DeferredTextureInfo>();

			CONFIG::DEBUG {
				private var debugHighlights:Dictionary;
				private var updateDebugTimer:TimedCall;
				private var layoutStartTime:uint;

				private var _debugTexture:Texture = Texture.fromColor(1, 1, 0xFFFF00FF);
			}

			CONFIG::MOBILE {
				public var nativeLogSignal:BaseSignal = null;
			}

			public function ViewLayout( viewFilename:String, parent:DisplayObjectContainer ) {
				_viewFilename = viewFilename;
				_consoleModel = ConsoleModel.instance;
				_parent = parent;
				_ser = new Serialization(false,true,true);
				_ser.setVariants(ACTIVE_VARIANTS);
				_ser.convertStringToNumber = getStringNumber;
				_ser.stringFilter = stringContextSubstitution;
				_ser.cacheByObject = true;
				UIFactory.addClassFactories(_ser);
				_objectSerializer = new Serialization(true);
				_objectSerializer.arrayMergeBehavior = Serialization.ARRAY_REPLACE;
			}

			public function initialize(resourceManager:ResourceManager, stats:StatsController, context:Dictionary = null):void {
				_resourceManager = resourceManager;
				_stats = stats;
				if(_context == null){
					initializeContext();
				}
				var keys:Array = [];
				for (var key:String in context) {
					keys.push(key);
				}
				for each (key in keys) {
					var curlyKey:String = makeCurlyKey(key);
					_context[curlyKey] = _contextValues[key] = context[key];
				}
				_evaluator.context = this;
			}

			public function initializeContext():void{
				_context = new Dictionary();
				_contextValues = new Dictionary();
			}

			public function get viewFilename():String {
				return _viewFilename;
			}

			public function set viewFilename( value:String ):void {
				_viewFilename = value;
			}

			public function get animation():AnimationManager {
				return _animationManager;
			}

			public function addResourceBundle( resourceBundle:ResourceBundle ):void {
				_resourceBundles.push( resourceBundle );
			}

			public function getResource( resourceName:String ):IResource {
				var result:IResource = null;
				var length:uint = _resourceBundles.length;
				for ( var index:int = 0; index < length && !result; index++ ) {
					result = _resourceBundles[index].getResource( resourceName );
				}
				return result;
			}

			private var _textureCache:Dictionary = new Dictionary();

			public function getScaleTextures( textureId:String ):Object {
				var textures:Object = _textureCache[textureId];
				if ( !textures ) {
					var scale9Rect:Rectangle = new Rectangle();
					var texture:Texture = getTexture( textureId, scale9Rect );
					if (texture != null) {
						var scale3Textures:Scale3Textures;
						if (scale9Rect.width > 0) {
							if (scale9Rect.height > 0) {
								textures = new Scale9Textures( texture, scale9Rect );
							} else {
								textures = new Scale3Textures( texture, scale9Rect.x, scale9Rect.width, Scale3Textures.DIRECTION_HORIZONTAL );
							}
						} else if (scale9Rect.height > 0) {
							textures = new Scale3Textures( texture, scale9Rect.y, scale9Rect.height, Scale3Textures.DIRECTION_VERTICAL );
						} else {
							textures = texture;
						}
					}
					if ( textures ) {
						_textureCache[textureId] = textures;
					}
				}
				return textures;
			}

			public function getImage( textureId:String ):DisplayObject {
				var scaleTextures:Object = getScaleTextures( textureId );

				var texture:Texture = scaleTextures as Texture;
				if (texture != null) {
					return new Image(texture);
				}

				var scale9Textures:Scale9Textures = scaleTextures as Scale9Textures;
				if (scale9Textures != null) {
					return new Scale9Image( scale9Textures );
				}

				var scale3Textures:Scale3Textures = scaleTextures as Scale3Textures;
				if (scale3Textures != null) {
					return new Scale3Image( scale3Textures );
				}

				CONFIG::DEBUG {
					if (canIgnoreTextureId(textureId) == false && _applyingDeferredTextures) {
						return new Image( _debugTexture );
					}
				}
				return null;
			}

			private function canIgnoreTextureId(textureId:String):Boolean {
				if (textureId == null) {
					return true;
				}

				if (textureId.indexOf("_Disable") >= 0) {
					return true;
				}

				if (textureId.indexOf("_Focus") >= 0) {
					return true;
				}

				if (textureId.indexOf("_Selected") >= 0) {
					return true;
				}

				return false;
			}

			public function getTexture( textureId:String, scaleRect:Rectangle = null, logWarn:Boolean = true ):Texture {
				var result:Texture = null;
				var atlas:TextureAtlas;
				if ( textureId != null && textureId != '' ) {
					var resource:IResource;
					var atlasScaleRect:Rectangle
					var length:uint = _resourceBundles.length;
					for ( var index:int = 0; index < length && !result; index++ ) {
						var bundle:ResourceBundle = _resourceBundles[index];
						resource = bundle.getResource( textureId );
						if ( resource ) {
							result = ( resource as TextureResource ).texture;
						}
						if ( !result ) {
							var resourceItems:Dictionary = bundle.getResources();
							for each ( resource in resourceItems ) {
								if ( resource is TextureAtlasResource ) {
									atlas = ( resource as TextureAtlasResource ).textureAtlas;
									if ( atlas ) {
										if (scaleRect) {
											atlasScaleRect = atlas.getScale9Rect(textureId);
											if (atlasScaleRect) {
												GraphicsUtil.copyRectangle( atlasScaleRect, scaleRect );
											}
										}
										var idx:int = textureId.lastIndexOf('/');
										if (idx > 0) {
											idx = textureId.lastIndexOf('/',idx-1);
											if (idx > 0) {
												textureId = textureId.substring(idx+1);
											}
										}
										result = atlas.getTexture(textureId);
									}
									else {
// TODO KWal: Silencing this error log for now until we have a better way to handle pending deferred resources.
//										_consoleModel.logError( "ViewLayout::getTexture() - TextureAtlas for " + resource.urls[0] + " is null" );
									}
								}
								if ( result ) {
									break;
								}
							}

						}
						if (result) {
							break;
						}
					}
				}

				if (!result) {
					if (logWarn && canIgnoreTextureId(textureId) == false) {
//						trace( "Error: ViewLayout::getTexture() - Unable to find textureId \"" + textureId + "\"" );
// TODO KWal: Silencing this error log for now until we have a better way to handle pending deferred resources.
//						_consoleModel.logError( "ViewLayout::getTexture() - Unable to find textureId \"" + textureId + "\"" );
					}
				}
				return result;
			}

			public function getTextureAtlas( textureId:String, nullable:Boolean = false ):TextureAtlas {
				var result:TextureAtlas = null;
				var resource:TextureAtlasResource = getResource( textureId ) as TextureAtlasResource;
				if ( resource ) {
					result = resource.textureAtlas;
				}
				if ( !result ) {
					var length:uint = _resourceBundles.length;
					for ( var index:uint = 0; index < length && !result; ++index ) {
						result = _resourceManager.getTextureAtlas( textureId, _resourceBundles[index] );
					}
				}
				return result;
			}

			public function getColor( textureId:String, defaultColor:uint = 0xBAADF00D ):uint {
				var result:uint;
				var atlas:TextureAtlas = getTextureAtlas( textureId );
				if ( !atlas ) {
					var length:uint = _resourceBundles.length;
					for ( var index:uint = 0; index < length && !result; ++index ) {
						result = _resourceManager.getColor( textureId, _resourceBundles[index], defaultColor );
					}
					if ( result == 0xBAADF00D ) {
						ConsoleModel.instance.logError( "Missing texture: " + textureId );
						result = 0;
					}
				} else {
					var color:String = atlas.getColor( textureId );
					if ( color == null ) {
						if ( defaultColor == 0xBAADF00D ) {
							ConsoleModel.instance.logError( "Missing color information: " + textureId );
						} else {
							result = defaultColor;
						}
					} else {
						result = uint( color );
					}
				}
				return result;
			}

			public function loadViewLayoutFromJson( jsonData:Object, resourceBundle:ResourceBundle, layoutDataModel:ILayoutDataModel ):Object {
				CONFIG::DEBUG {
					removeDebugHighlights();
				}
					viewResourcesLoadedSignal.clear();
				layoutCompleteSignal.clear();
				childrenLayoutCompleteSignal.clear();
				var data:Object = (jsonData is String) ? JSON.parse( String(jsonData) ) : jsonData;

				if ( !data ) {
					_consoleModel.logError( "ViewLayout::loadViewLayoutFromJson() - " + _viewFilename + " invalid layout JSON" );
					return null;
				}

				data = LayoutUtil.processExtends( data, layoutDataModel, "root" );
				createDataModels( data, resourceBundle );
				if (data.hasOwnProperty("simple")) {
					_simple = data["simple"] is Boolean ? (data["simple"] ? 2 : 0) : data["simple"];
				}
				_styles = LayoutUtil.parseStyles( _viewFilename, data, _resourceManager, resourceBundle, _context, collectTexturesDeferrable );
				_help = LayoutUtil.parseHelp( _viewFilename, data, _resourceManager, resourceBundle, _context );
				_uniqueIdGroups = new Dictionary();
				LayoutUtil.processStyles( _viewFilename,  data, _styles, _resourceManager, resourceBundle, _context, _uniqueIdGroups );
				LayoutUtil.processOverrides( data, _styles, _uniqueIdGroups );
				LayoutUtil.addIds( data, _styles, _uniqueIdGroups );
				//trace(_ser.toJsonString(data));
				LayoutUtil.collectControlTextureReferences( _viewFilename, data, _resourceManager, resourceBundle, _context, collectTexturesDeferrable );
				parseAnimations( data );
				parseAssets( data, resourceBundle );
				parseSound( data );
				childrenLayoutCompleteSignal.addOnceNamed( childrenLayoutComplete, "ViewLayout_loadViewLayoutFromJson");
				createControls( data, resourceBundle, Type.getTypeName(_parent) );

				return data;
			}

			private function parseAnimations( data:Object ):void {
				_animationManager.clear();
				if (data.hasOwnProperty("animations")) {
					_animationManager.initialize( data["animations"], this );
				}
			}

			protected function createControls( layoutData:Object, resourceBundle:ResourceBundle, viewName:String ):void {
				UIFactory.viewName = viewName;
				UIFactory.stats = _stats;
				var newControls:Dictionary = new Dictionary();
				_controlConfigs = newControls;
				_controlGroups = new Dictionary();
				_controlGroupIndexes = new Dictionary(true);
				_controlList = new Vector.<ConfigurableControl>();
				_tempList = new Vector.<ConfigurableControl>();
				if (layoutData.hasOwnProperty("controls")) {
//					var cache:Vector.<ConfigurableControl> = configuredControlCache[_viewFilename];
//					if (cache) {	// fterTODO: Enable creating from cache when we're ready to resume work on this
//						createControlsFromCache( cache, resourceBundle );
//						createControlGroupsFromCache();
//					} else
					{
						createControlsInternal( layoutData, "controls", null, newControls, _controlList, resourceBundle );
						createControlGroups(_controlList);
					}
				}

				UIFactory.viewName = null;
				UIFactory.stats = null;
			}

/*			private function createControlsFromCache(cache:Vector.<ConfigurableControl>, resourceBundle:ResourceBundle):void {
				var savedCheckVariants:Boolean = _ser.checkVariants;
				_ser.checkVariants = false;

				var len:int = cache.length;
				for (var i:int=0; i<len; i++ ) {
					var container:ConfigurableControl = cache[i];
					var control:DisplayObject = _controls[ container.id ] = _ser.fromObject( container.finalData, container.controlType, null, null, true ) as DisplayObject;
					control.name = container.id;
					var parentId:String = container.parent ? container.parent.id : null;
					if (parentId == null) {
						_parent.addChild( control );
					} else {
						(getControlForContainer(_controls[parentId]) as DisplayObjectContainer).addChild( control );
					}
					_controlConfigs[ container.id ] = container;
					_controlList[i] = container;
				}
				LayoutUtil.textureReferencesFromCache( _viewFilename, resourceBundle );
				_ser.checkVariants = savedCheckVariants;
			}
*/

/*			private function initControlsFromCache(): void {
				var cache:Vector.<ConfigurableControl> = configuredControlCache[_viewFilename];
				var len:int = cache.length;

				for (var i:int=0; i<len; i++ ) {
					var container:ConfigurableControl = cache[i];
					var control:DisplayObject = getControlForContainer(container);
					applyTextures( container );
					_ser.copyFields( container.finalData, control, container.controlType );
					if ( control is LocLabel ) {
						LocLabel(control).invalidateRenderer( FeathersControl.INVALIDATION_FLAG_STYLES );
					}
					if ( control is LayoutGroup ) {
						LayoutGroup(control).leaveChildrenAlone = true;
					}
					CONFIG::DEBUG {
						if (container.finalData.hasOwnProperty("debug")) {
							makeDebugHighlight( control, container.finalData["debug"] );
							//						trace(control.name,
							//							"x:"+String(Math.round(control.x*100.0)/100.0),
							//							"y:"+String(Math.round(control.y*100.0)/100.0),
							//							"w:"+String(Math.round(control.width*100.0)/100.0),
							//							"h:"+String(Math.round(control.height*100.0)/100.0),
							//							"pw:"+String(Math.round(control.parent.width*100.0)/100.0),
							//							"ph:"+String(Math.round(control.parent.height*100.0)/100.0) );
						}
					}
				}
			}
*/
			private function createControlGroups(list:Vector.<ConfigurableControl>):void {

//				var groupCache:Dictionary= controlGroupCache[_viewFilename];
//				if (groupCache == null) {
//					groupCache = controlGroupCache[_viewFilename] = new Dictionary();
//				}

				for (var i:int=0; i<list.length; i++) {
					var container:ConfigurableControl = list[i];
					var config:Object = container.config;
					var name:String = config["group"];
					if (name) {
						var group:Vector.<DisplayObject> = _controlGroups[name];
//						var cachedGroup:Vector.<String> = groupCache[name];
						if (!group) {
							group = _controlGroups[name] = new Vector.<DisplayObject>();
//							cachedGroup = groupCache[name] = new Vector.<String>();
						}
						var control:DisplayObject = getControlForContainer(container);
						var groupLength:int = group.length;
						_controlGroupIndexes[control] = groupLength;
						group[groupLength] = control;
//						cachedGroup.push( control.name );
					}
				}
			}

/*			private function createControlGroupsFromCache(): void {
				var cache:Dictionary = controlGroupCache[_viewFilename];
				if ( cache ) {
					for ( var name:String in cache ) {
						var cachedGroup:Vector.<String> = cache[name];
						var group:Vector.<DisplayObject> = _controlGroups[name] = new Vector.<DisplayObject>();
						var groupLength:int = 0;
						for each ( var id:String in cachedGroup ) {
							var control:DisplayObject = _controls[id];
							group[groupLength] = control;
							_controlGroupIndexes[control] = groupLength;
							groupLength++;
						}
					}
				}
			}
*/

//			private static var configuredControlCache:Dictionary = new Dictionary(); // viewLayoutFilename => Vector.<ConfigurableControl>
//			private static var controlGroupCache:Dictionary = new Dictionary();		 // viewLayoutFilename => { id => Vector.<String> }

			public static function clearCache(all:Boolean = false):void {
				LayoutUtil.clearCache(all);
				_lookup = new Dictionary();
				_expressions = new Dictionary();
//				if (all) {
//					configuredControlCache = new Dictionary();
//				}
			}

			public function dispose():void {
				for each (var container:ConfigurableControl in _controlList) {
					container.dispose();
				}
				if(_childViews){
					for each (var childView:BaseView in _childViews){
						childView.dispose();
					}
				}
				var key:*;
				for (key in _controlGroups) {
					delete _controlGroups[key];
				}
				_controlGroups = null;
				for (key in _controlGroupIndexes) {
					delete _controlGroupIndexes[key];
				}
				_controlGroupIndexes = null;
				for (key in _delayedControls) {
					delete _delayedControls[key];
				}
				_delayedControls = null;
				for (key in _controls) {
					delete  _controls[key];
				}
				_controls = null;
				_controlList = null;
				_rootControl = null;
				_currentControl = null;
				removeAllBindings();

				_parent = null;
				
				_ser.clearAllVariants();
				_ser.convertStringToNumber = null;
				_ser.stringFilter = null;
				_ser = null;
			}

			public function createDelayedControls( id:String, complete:BaseSignal=null ):void {
				var data:Object = _delayedControls[id];
				if (data) {
					delete _delayedControls[id];
					var delayLayout:int = data["delayLayout"];
					delete data["delayLayout"];
					var delayName:String = data["_delayName"]; delete data["_delayName"];
					if (delayName) {
						var pm:BaseProcessManager = data["_processManager"] as BaseProcessManager;
						pm.removeByName(delayName);
					}
					var parent:ConfigurableControl = data["_parent"]; delete data["_parent"];
					var sibling:DisplayObject = data["_sibling"]; delete data["_sibling"];
					var newControls:Dictionary = data["_newControls"]; delete data["_newControls"];
					var resourceBundle:ResourceBundle = data["_resourceBundle"]; delete data["_resourceBundle"];
					var nesting:int = data["_nesting"]; delete data["_nesting"];
					var tempList:Vector.<ConfigurableControl> = new Vector.<ConfigurableControl>();
					createControlsInternal( data, null, parent, newControls, tempList, resourceBundle, nesting );
					createControlGroups(tempList);
					var addTo:DisplayObjectContainer = parent ? (getControl( parent.id ) as DisplayObjectContainer) : _parent;
					var siblingIndex:int = addTo.getChildIndex(sibling);
					addControlsAsChildrenInternal( tempList, addTo, siblingIndex+1 );
					if (_simple != 0) {
						layoutInstantiatedControls(tempList,_simple==1);
						layoutComplete(tempList,complete);
					} else {
					layoutPhase0(tempList);
					ProcessManager.instance.delayCall( layoutPhase1, 0, tempList, true, complete );
					}
					var len:int = tempList.length;
					for (var i:int=0; i<len; i++) {
						_controlList[_controlList.length] = tempList[i];
					}
				data['delayLayout'] = delayLayout; //restore the setting once we are done.
				} else if (complete != null) {
					complete.dispatch();
				}
			}

			private function createControlsInternal( layoutData:Object, controlsField:String, parent:ConfigurableControl, newControls:Dictionary, list:Vector.<ConfigurableControl>, resourceBundle:ResourceBundle, nesting:int = 0 ):void {
				var controlData:Array = !controlsField ? [layoutData] : layoutData[controlsField];
				var len:int = controlData.length;
				var layer:String = null;
				var hasDepth:Boolean = false;
				var depth:int = 0;

				_rootControl = null;
				for (var i:int=0; i<len; i++) {
					var data:Object = controlData[i];

					if (configHasProperty(data,"includeInLayout")) {
						var includeInLayout:Boolean = Boolean(getConfig( data, "includeInLayout" ));
						if ( !includeInLayout ) {
							continue;
						}
					}

					var id:String = data["id"];	// LayoutUtil.getId( data, controlType.name );

					if (configHasProperty(data,"delayLayout")) {
						var delay:int;
						var delayValue:Object = getConfig(data,"delayLayout");
						if (delayValue is String) {
							delay = (_delay += int(delayValue)*4);
						} else {
							delay = int(delayValue)*4;
						}
						if (delay != 0) {
							data["_parent"] = parent;
							data["_sibling"] = control;
							data["_newControls"] = newControls;
							data["_resourceBundle"] = resourceBundle;
							data["_nesting"] = nesting;
							_delayedControls[id] = data;
							if (delay >= 0) {
								var baseView:BaseView = _parent as BaseView;
								if (baseView) {
									baseView.viewProcessManager.delayCallFramesNamed(createDelayedControls,delay,id,id);
									data["_delayName"] = id;
									data["_processManager"] = baseView.viewProcessManager;
								}
							}
							continue;
						}
					}

					if (data.hasOwnProperty("context")) {
						setContextValues(data["context"]);
					}

					var repeat:int = 0;
					if (configHasProperty(data,"repeat")) {
						repeat = getConfigNumber(data,"repeat");
					}

					do {
						id = data["id"];

						if ( id == null ) {
							throw new Error("Control with null id.");
						}
						var controlType:Type = LayoutUtil.getType(data);
						if (controlType == null) {
							throw new Error("Control with id \""+id+"\" missing "+Serialization.TYPE_FIELD);
						}
						if (newControls && newControls[id] != undefined) {
							do {
								var newId:String = (Math.random() * 10000) + id;
							} while (newControls[newId] != undefined);
							id = newId;
						}
						layer = data.hasOwnProperty("layer") ? data["layer"] : null;
						var container:ConfigurableControl;
						var control:DisplayObject;
						control = _ser.fromObject( data, controlType, null, null, false ) as DisplayObject;
						_ser.disposeStack();
						if (_rootControl == null) {
							_rootControl = control;
						}
						_controls[id] = control;
						container = new ConfigurableControl( data, layer );
						if (data.hasOwnProperty("name") == false) {
							control.name = id;
						}
						if (newControls) {
							newControls[id] = container;
						} else {
							container.control = control;
						}
						var asBaseView:BaseView = control as BaseView;
						if (asBaseView) {
							addToChildViews( asBaseView );
							asBaseView.layout.setContextValues(this._contextValues);
							if (data.hasOwnProperty("context")) {
								asBaseView.setContextValues(data["context"]);
							}
							asBaseView.layout.viewResourcesLoadedSignal.addOnce(childViewLoaded);
							asBaseView.layout.layoutCompleteSignal.addOnce(childViewLayoutComplete);
							viewResourcesLoadedSignal.threshold++;
							layoutCompleteSignal.threshold++;
							childrenLayoutCompleteSignal.threshold++;
						}
						container.initialize( id, control, parent, nesting, list.length, controlType, (data.hasOwnProperty("depth") ? data["depth"] : (++depth)) );
						list[list.length] = container;
						var index:int = _controlList.length;
						if (control is DisplayObjectContainer && data.hasOwnProperty("children")) {
							createControlsInternal( data, "children", container, newControls, list, resourceBundle, nesting+1 );
						}
						container.originalNumChildren = list.length - index;
					} while (--repeat > 0);
				}
			}

			public function addToChildViews( childView:BaseView ):void {
				if(!_childViews){
					_childViews = new Vector.<BaseView>();
				}

				childView.addEventListener( Event.REMOVED_FROM_STAGE, onChildViewRemoved );
				_childViews.push( childView );
			}

			private function onChildViewRemoved( event:Event ):void {
				var childView:BaseView = event.target as BaseView;
				if (childView) {
					var index:int = _childViews.indexOf( childView );
					if(index != -1){
//						_consoleModel.logDebug("Removing Child View ["+childView.name+"] from "+this._viewFilename);
						_childViews.splice( index, 1 );
					}
				}

				event.target.removeEventListener( Event.REMOVED_FROM_STAGE, onChildViewRemoved );
			}

			public function setContextValues( context:Object ):void {
				if (context != null) {
					for (var key:String in context) {
						setContextValue( key, context[key] );
					}
				}
			}

			public function setVariable( name:String, value:* ):* {
				return setContextValue( name, value );
			}

			public function getVariables(): Dictionary {
				return _contextValues;
			}

			public function setContextTags( tags:Vector.<String> ) : void {
				_contextTags = tags;
			}

			public function getContextValue( name:String ):* {
				var result:* = _contextValues[name];
				if ( result == null ) {
					// check experiment tags, return Boolean: true if tag present, false if not.
					if ( _contextTags ) {
						result = Boolean( _contextTags.indexOf( name ) != -1 );
					}
				}
				return result;
			}

			public function pulseContextValue( name:String, value:*=true ):void {
				if(_childViews){
					var childView:BaseView;
					for each ( childView in _childViews ){
						childView.layout.pulseContextValue( name, value );
					}
				}
				setContextValue( name, value );
				_setContextValue( name, null );
			}

			private function _setContextValue( name:String, value:* ):* {
				if(_context == null){
					initializeContext();
				}
				if (value is String) {
					var str:String = value as String;
					if (str.indexOf("{") == 0) {
						value = getAsReference( value, null );
					} else if (str.indexOf("(") == 0) {
						value = eval(str);
					}
				}
				var key:String = makeUnCurlyKey(name);
				_contextValues[key] = value;
				var curlyKey:String = makeCurlyKey(name);
				_context[curlyKey] = value;
				return value;
			}

			public function setContextValue( name:String, value:*, bAlwaysAllowChecks:Boolean = false ):* {
				if(_childViews){
					var childView:BaseView;
					for each ( childView in _childViews ){
						childView.layout.setContextValue( name, value, bAlwaysAllowChecks);
					}
				}
				if(_context == null){
					initializeContext();
				}
				var oldValue:* = getContextValue(name);
				value = _setContextValue( name, value );
				if (value != oldValue || bAlwaysAllowChecks) {
					checkBindings(name);
					checkTriggers(name);
				}
				return value;
			}

			public function broadcastContextValue( name:String ):void {
				if(_childViews){
					var childView:BaseView;
					for each ( childView in _childViews ){
						childView.layout.broadcastContextValue( name );
					}
				}
				if (_context[name] == undefined) {
					_setContextValue(name,1);
				}
				checkTriggers(name);
			}

			private function checkBindings( name:String ):void {
				if (_bindings) {
					var bound:Vector.<BindingInfo> = _bindings[name];
					if (bound) {
						for each (var info:BindingInfo in bound) {
							info.target[info.fieldName] = this.evaluate( info.expression );
						}
					}
				}
			}

			private function checkTriggers( name:String ):void {
				if (_triggers) {
					var triggers:Vector.<TriggerInfo> = _triggers[name];
					if (triggers) {
						for each (var triggerInfo:TriggerInfo in triggers) {
							var result:* = this.evaluate( triggerInfo.expression );
							if (result != null && result != undefined && !(result === false)) {
								var params:Array = triggerInfo.params;
								if (params == null) {
									triggerInfo.func();
								} else {
									switch (params.length) {
										case 0: triggerInfo.func(); break;
										case 1: triggerInfo.func(params[0]); break;
										case 2: triggerInfo.func(params[0],params[1]); break;
										case 3: triggerInfo.func(params[0],params[1],params[2]); break;
										case 4: triggerInfo.func(params[0],params[1],params[2],params[3]); break;
										case 5: triggerInfo.func(params[0],params[1],params[2],params[3],params[4]); break;
										default:
											throw new Error("Invalid number of trigger parameters.");
									}
								}
							}
						}
					}
				}
			}

			/**
			 * Create a display object from a style declared in the layout data.
			 * NOTE: Processing layout data is usually a multi-frame opperation.
			 *       This function tries to do basic layout in one frame for now, and may not work for complex layouts and Feathers controls.
			 *       The first use for this is for basic graphics and starling objects, not Features controls and layout groups.
			 */
			public function instantiateStyle( styleName:String, parent:DisplayObjectContainer, resourceBundle:ResourceBundle, context:Object = null ):DisplayObject {
				var oldControls:Dictionary = _controls;
				var oldControlGroups:Dictionary = _controlGroups;
				var oldControlGroupIndexes:Dictionary = _controlGroupIndexes;

				_controls = new Dictionary(true);
				_controlGroups = new Dictionary();
				_controlGroupIndexes = new Dictionary(true);
				var uniqueIdGroups:Dictionary = new Dictionary();

				var style:Object = getStyleData( styleName );
				var data:Object = LayoutUtil.getStyledConfig( style, _styles, true, uniqueIdGroups);
				_tempList.length = 0;
				// Add any run-time specified context values
				setContextValues( context );
				// Create a display object from the style and recursively create all children
				createControlsInternal( data, null, null, null, _tempList, resourceBundle );

				var addTo:DisplayObjectContainer = parent ? parent : _parent;
				addControlsAsChildrenInternal( _tempList, addTo );

				layoutInstantiatedControls(_tempList);

				var container:ConfigurableControl = _tempList[0];

				// The commented-out lines below don't work. _ser.fromObject() with createOnly=true results in un-initialized controls when not caching.
				var control:DisplayObject = getControlForContainer(container);
				//			// TODO: check last parameter createOnly
				//			var control:DisplayObject = _controls[ container.id ] = _ser.fromObject( container.finalData, container.controlType, null, null, true ) as DisplayObject;
				if (!parent) {
					control.removeFromParent();
				}

				var len:int = _tempList.length;
				for ( var i:int = 0; i < len; i++ ) {
					_tempList[i].dispose();
					_tempList[i] = null;
				}
				_tempList.length = 0;

				if (data.hasOwnProperty("name") == false) {
					control.name = styleName;
				}

				_controls = oldControls;
				_controlGroups = oldControlGroups;
				_controlGroupIndexes = oldControlGroupIndexes;

				return control;
			}

			private function layoutInstantiatedControls(list:Vector.<ConfigurableControl>,doPhase2:Boolean=true):void {
				layoutPhase0(list);
				var len:int = list.length;
				var i:int;
				// Validate layout feathers controls as would normally happen on next frame
				if (doPhase2) {
					for (i=0; i<len; ++i) {
						var fc:FeathersControl = getControlForContainer( list[i] ) as FeathersControl;
						if (fc && !(fc is Label)) {
							fc.validate();
						}
					}
				}
				// Phase 1
				for (i=0; i<len; ++i) {
					positionAndSizeControl( list[i], false );
				}
				// Validate layout groups as would normally happen on next frame
				for (i=0; i<len; ++i) {
					if (list[i].controlIsLayoutGroup) {
						var layoutGroup:LayoutGroup = getControlForContainer( list[i] ) as LayoutGroup;
						//layoutGroup.invalidate(FeathersControl.INVALIDATION_FLAG_SIZE);
						layoutGroup.validate();
					}
				}
				// Phase 2
				if (doPhase2) {
				for (i=0; i<len; ++i) {
					positionAndSizeControl( list[i], true );
				}
			}
			}

			private static function orderSort(a:ConfigurableControl, b:ConfigurableControl):Number {
				if (a.order < b.order) {
					return -1;
				} else if (a.order > b.order) {
					return 1
				} else {
					return 0;
				}
			}

			private static function nestingSort(a:ConfigurableControl, b:ConfigurableControl):Number {
				if (a.nesting < b.nesting) {
					return -1;
				} else if (a.nesting > b.nesting) {
					return 1
				} else {
					if (a.order < b.order) {
						return -1;
					} else if (a.order > b.order) {
						return 1
					} else {
						return 0;
					}
				}
			}

			private static function depthSort(a:ConfigurableControl, b:ConfigurableControl):Number {
				if (a.nesting < b.nesting) {
					return -1;
				} else if (a.nesting > b.nesting) {
					return 1
				} else {
					if (a.depth < b.depth) {
						return -1;
					} else if (a.depth > b.depth) {
						return 1
					} else {
						return 0;
					}
				}
			}

			protected function childViewLayoutComplete():void {
				layoutCompleteSignal.dispatch();
				childrenLayoutCompleteSignal.dispatch();
			}

			protected function childViewLoaded():void {
				viewResourcesLoadedSignal.dispatch();
			}

			protected function removeControl(id:String):void {
				var control:DisplayObject = _controlConfigs[id].control;
				if (control != null) {
					control.removeFromParent(true);
					delete _controlConfigs[id];
				}
			}

			final public function hasControl(id:String):Boolean {
				return getControl(id,true) != null;
			}


			final public function getControlNoWarn(id:String):DisplayObject {
				return getControl(id,true);
			}

			final public function getControlById(id:String,dontWarn:Boolean=false):DisplayObject {
				var result:DisplayObject = null;
				if (_controls) {
					result = _controls[id];
					if (result == null && !dontWarn) {
						_consoleModel.logWarning("No control named "+id+" found.  (Did not check groups)");
					}
				} else if (!dontWarn) {
					_consoleModel.logWarning("List of controls is null, searching for id "+id);
				}
				return result;
			}

			final public function getControl(id:String,dontWarn:Boolean=false,index:int=-1):DisplayObject {
				if ((id == "view" || id == "this") && _parent)
					return BaseView.getViewForControl(_parent);

				if (index >= 0) {
					return getControlFromGroup(id,index,dontWarn);
				}

				var bracket:int = id.indexOf("[");
				if (bracket != -1) {
					var indexStr:String = id.substring(bracket+1,id.length-1);
					var indexNum:Number = Number(indexStr);
					if (indexNum!=indexNum) {
						indexNum = Number(getAsReference(indexStr,null));
					}
					if (indexNum==indexNum) {
						id = id.substr(0,bracket);
						return getControlFromGroup(id,int(indexNum));
					}
				}
				var result:DisplayObject = _controls ? _controls[id] : null;
				if (result == null) {
					result = getControlFromGroup(id,0,true);
					if (result != null) {
						_controls[id] = result;
					} else {
						if (!dontWarn) {
							_consoleModel.logWarning("No control named "+id+" found.");
						}
					}
				}
				return result;
			}

			/**
			 * Gives the number of controls in a specified control group.
			 * @param id Group to count controls for.
			 * @return Number of controls in group.
			 */
			public function getControlGroupLength(id:String):uint {
				if(!_controlGroups[id]) {
					return 0;
				}
				var group:Vector.<DisplayObject> = _controlGroups[id] as Vector.<DisplayObject>;
				return group.length;
			}

			public function getControlFromGroup(id:String,index:int,dontWarn:Boolean=false):DisplayObject {
				if ( !_controlGroups ) {
					if (!dontWarn) _consoleModel.logWarning("Control groups not initialized.");
					return null;
				}
				var group:Vector.<DisplayObject> = _controlGroups[id] as Vector.<DisplayObject>;
				if (group) {
					if (index < group.length && index >= 0) {
						return group[index];
					} else {
						if (!dontWarn) _consoleModel.logWarning("Control group "+id+" index "+String(index)+" not between 0 and "+String(group.length-1));
						return null;
					}
				} else {
					if (!dontWarn) _consoleModel.logWarning("No group named "+id+" found.");
					return null;
				}
			}

			public function getControlGroupIndex(obj:DisplayObject):int {
				var index:Object = _controlGroupIndexes[obj];
				if (index != null) {
					return int(index);
				} else {
					return -1;
				}
			}

			public function addControlsAsChildren():void {
				CONFIG::DEBUG {
					layoutStartTime = getTimer();
				}
				addControlsAsChildrenInternal(_controlList,_parent);
//				var cache:Vector.<ConfigurableControl> = configuredControlCache[_viewFilename];
//				if ( cache ) {
//					initControlsFromCache();
//				}
				childrenLayoutCompleteSignal.dispatchAsync();
			}

			private function getControlForContainer(container:ConfigurableControl):DisplayObject {
				return container.control ? container.control : _controls[container.id];
			}

			protected function addControlsAsChildrenInternal(list:Vector.<ConfigurableControl>, parent:DisplayObjectContainer, atIndex:int = -1):void {
				list.sort( depthSort );
				var len:int = list.length;
				var container:ConfigurableControl;
				var control:DisplayObject;
				var i:int;
				if (_rootControl) {
					_rootControl.addEventListener( Event.REMOVED_FROM_STAGE, onRootControlRemoved );
				}
				for (i=0; i<len; ++i) {
					container = list[i];
					control = getControlForContainer(container);
					_currentControl = control;
					var asDisplayObjectContainer:DisplayObjectContainer = container.parent ? getControlForContainer(container.parent) as DisplayObjectContainer : null;
					var addTo:DisplayObjectContainer = asDisplayObjectContainer ? asDisplayObjectContainer : parent;
					if ( container.layer != null && container.layer != '' && addTo is BaseView ) {
						var baseView:BaseView = addTo as BaseView;
						if ( !baseView.layerContains( container.layer, control ) ) {
							baseView.layerAddChild( container.layer, control );
						}
					} else if ( !addTo.contains( control ) ) {
						if (atIndex == -1) {
							control = addTo.addChild( control );
						} else {
							control = addTo.addChildAt( control, atIndex );
							atIndex = -1;	// Only applies to the first one.
						}
						if (control == null) {
							// If addChild returned null, the child was removed by the control
							list.splice(i--,1);
							len--;
						}
					}
				}

				list.sort( orderSort );
				for (i=0; i<len; ++i) {
					container = list[i];
					control = getControlForContainer(container);
					_currentControl = control;
					// Copy all fields since the Aeon desktop theme happens when added
					LayoutUtil.setContextValues(container.config,_context);
					_ser.copyFields( container.config, control );
					// Do context substitution on translated text
					if (control as Label) {
						var newText:String = LayoutUtil.contextSubstitution((control as Label).text, _context);
						if (control is LocLabel) {
							(control as LocLabel).plainText = newText;
						} else {
							(control as Label).text = newText;
						}
					}
				}
				_currentControl = null;
			}

			private function onRootControlRemoved():void {
				this._removed = true;
				if (_rootControl) {
					_rootControl.removeEventListener( Event.REMOVED_FROM_STAGE, onRootControlRemoved );
				}
			}

			protected function childrenLayoutComplete():void {
//				var cache:Vector.<ConfigurableControl> = configuredControlCache[_viewFilename];
//				if (cache) {
//					var len:int = cache.length;
//					for (var i:int=0; i<len; i++ ) {
//						var container:ConfigurableControl = cache[i];
//						applyTextures( container );
//					}
//					layoutCompleteSignal.dispatchAsync();
//				} else
				{
					if (!_removed) {
						if (_simple != 0) {
							try {
								layoutInstantiatedControls(_controlList,_simple==1);
							} catch (e:Error) {
								ErrorManager.reportClientError("Error in layoutInstantiatedControls.",null,e.getStackTrace(),ErrorManager.getConsoleTrace(ConsoleModel.instance),{
									'view_filename': _viewFilename,
									'control': (_currentControl ? _currentControl.name : "null")
								});
							}
							layoutComplete(_controlList);
						} else {
							layoutPhase0(_controlList);
							ProcessManager.instance.delayCall( layoutPhase1, 0, _controlList );
						}
					}
				}
			}

			private function layoutPhase0(list:Vector.<ConfigurableControl>):void {
				_layoutPhase = 0;
				var container:ConfigurableControl;
				var control:DisplayObject;
				var i:int;
				var len:int = list.length;

				for (i=0; i<len; ++i) {
					container = list[i];
					control = getControlForContainer(container);
					applyTextures(container);
					var fc:FeathersControl = control as FeathersControl;
					if (fc && !(fc is Label) ) {
						fc.invalidate();	// Sliders in particular weren't re-skinning properly
					}
					container.bounds = null;
					container.totalChildHeightPercentage = 0.0;
					container.totalChildWidthPercentage = 0.0;
					container.totalChildHeightConcrete = 0.0;
					container.totalChildWidthConcrete = 0.0;
				}
				invalidateControlsInternal(true,true,true,list);
			}

			private function layoutPhase1(list:Vector.<ConfigurableControl>,scheduleNextPhase:Boolean=true, completeSignal:BaseSignal=null):void {
				_layoutPhase = 1;
				if (_removed) {
					return;
				}
				list.sort( nestingSort );
				var len:int = list.length;
				for (var i:int=0; i<len; ++i) {
					var container:ConfigurableControl = list[i];
					var control:DisplayObject = getControlForContainer(container);
					positionAndSizeControl( container, false );
				}
				if (scheduleNextPhase && !_removed) {
					ProcessManager.instance.delayCall( layoutPhase2, 0, list, scheduleNextPhase, completeSignal );
				}
			}

			private function layoutPhase2(list:Vector.<ConfigurableControl>,scheduleNextPhase:Boolean=true, completeSignal:BaseSignal=null):void {
				_layoutPhase = 2;
				if (_removed) {
					return;
				}
				var len:int = list.length;
				for (var i:int=0; i<len; ++i) {
					positionAndSizeControl( list[i], true );
				}
				if (scheduleNextPhase && !_removed) {
					ProcessManager.instance.delayCall( layoutPhase3, 0, list, completeSignal );
				}
			}

			private static var EXCLUDE_FIELDS:Array = [
				"x","y","z",
				"_type","id","style","overrides","children","layer","group","_group",
				"scale","depth","pivot","horizontalCenter","verticalCenter",
				"left","right","top","bottom","textureId","textureAtlasId",
				"iconScale","fontId","backgroundFocusedTextureId",
				"backgroundTextureId","backgroundDisabledId","scaleMode",
				"animation","iconId","defaultTextureId","disabledTextureId", "disabledIconId",
				"downTextureId","hoverTextureId","defaultIconId","defaultSelectedTextureId",
				"defaultSelectedIconId","onTextureId","offTextureId","minimumTrackTextureId",
				"upIconId","downIconId","hoverIconId","fillTextureId"];

			private static var USE_CONFIG_FIELDS:Array = ["label","text","plainText","debug"];

			private function layoutPhase3(list:Vector.<ConfigurableControl>, completeSignal:BaseSignal=null):void {
				_layoutPhase = 3;

				if (_rootControl) {
					_rootControl.removeEventListener( Event.REMOVED_FROM_STAGE, onRootControlRemoved );
				}

				if (_removed) {
					return;
				}

				invalidateControlsInternal(true,true,true,list);
				// Once everything has been re-re-re-layed out...  complete
				layoutComplete(list,completeSignal);

				// DISABLE CONTROL CACHING for now.
				return;
				/*
				// Cache any final data values not cached thus far
				if (_controlList == list) {
				list.sort( depthSort );
				configuredControlCache[_viewFilename] = _controlList;
				const controlLength:int = _controlList.length;
				for (var i:int=0; i<controlLength; ++i) {
				var container:ConfigurableControl = _controlList[i];
				var control:DisplayObject = getControlForContainer(container);
				container.finalData["x"] = control.x;
				container.finalData["y"] = control.y;
				if ( container.controlIsLayoutGroup ) {
				if ( control.width != 0 ) {
				container.finalData["width"] = control.width;
				}
				if ( control.height != 0 ) {
				container.finalData["height"] = control.height;
				}
				}
				for (var property:String in container.config) {
				var variant:String = getVariantName( property );
				if (variant == null || ACTIVE_VARIANTS.indexOf(variant) >= 0 ) {
				var baseProperty:String = getBaseFieldName( property );
				if (EXCLUDE_FIELDS.indexOf(baseProperty) ==-1) {
				if (property != "debug" && control.hasOwnProperty(property) == false) {
				CONFIG::DEBUG {
				trace("ERROR: Unknown property in layout "+_viewFilename+": "+control+' "'+control.name+'" . '+property);
				// throw new Error("Unknown property in layout "+_viewFilename+": "+control+' "'+control.name+'" . '+property);
				}
				continue;
				}
				if (USE_CONFIG_FIELDS.indexOf(baseProperty) >= 0) {
				container.finalData[baseProperty] = container.config[baseProperty];
				} else {
				// Because of how Feathers manages scaled width & height, we have to divide out the
				// scale when caching these properties.
				if ( baseProperty == "width" ) {
				container.finalData[baseProperty] = control.width / control.scaleX;
				}
				else if ( baseProperty == "height" ) {
				container.finalData[baseProperty] = control.height / control.scaleY;
				}
				else {
				container.finalData[baseProperty] = control[baseProperty];
				}
				}
				}
				}
				}
				// We are getting double negatives when scaleX or scaleY are negative -
				// for example, the width will be negative, and we'll still have a negative scale.
				if ( container.finalData.hasOwnProperty("width") ) {
				var w:Number = container.finalData["width"];
				if ( w < 0 ) {
				container.finalData["width"] = -w;
				}
				}
				if ( container.finalData.hasOwnProperty("height") ) {
				var h:Number = container.finalData["height"];
				if ( h < 0 ) {
				container.finalData["height"] = -h;
				}
				}
				}
				*/
			}

			private function layoutComplete(list:Vector.<ConfigurableControl>, completeSignal:BaseSignal=null):void {
				if (list == _controlList) {
					layoutCompleteSignal.dispatchAsync();
				}
				if (completeSignal) {
					completeSignal.dispatchAsync();
				}

//				CONFIG::DEBUG {
//					var now:uint = getTimer();
//					_consoleModel.logDebug(this.viewFilename+" layout complete in "+(now-layoutStartTime)+"MS");
//				}
			}

			private function invalidateControlsInternal(layoutGroups:Boolean=true,labels:Boolean=false,buttons:Boolean=false,list:Vector.<ConfigurableControl>=null):void {
				if (list==null) {
					list = _controlList;
				}
				var len:int = list.length;
				var container:ConfigurableControl;
				var i:int;
				for (i=0; i<len; ++i) {
					container = list[i];
					var control:DisplayObject = getControlForContainer(container);
					var layoutGroup:LayoutGroup = control as LayoutGroup;
					if (layoutGroup) {
						layoutGroup.invalidate();
					}
					// TODO: Should check if scale has changed before doing an invalidate.
					if (labels) {
						var label:Label = control as Label;
						if (label) {
							label.invalidate(FeathersControl.INVALIDATION_FLAG_SIZE);
						}
					}
					// TODO: Should check if scale has changed before doing an invalidate.
					if (buttons) {
						var button:Button = control as Button;
						if (button) {
							button.invalidate(FeathersControl.INVALIDATION_FLAG_SIZE);
						}
					}
				}
			}

			public function invalidateControls(layoutGroups:Boolean=true,labels:Boolean=false,buttons:Boolean=false):void {
				invalidateControlsInternal(layoutGroups,labels,buttons,_controlList);
			}

			public function skinButtonControl (controlId:String, textureId:String, index:int = -1):void {
				skinControl( controlId, textureId+"_NonFocus","defaultSkin", index );
				skinControl( controlId, textureId+"_Selected","hoverSkin", index );
				skinControl( controlId, textureId+"_Disable","disabledSkin", index );
			}
			
			public function skinControl( controlId:String, textureId:String, skinId:String = 'texture', index:int = -1):Boolean {
				var control:DisplayObject = getControl( controlId, false, index );
				if ( control ) {
					var bSkinApplied:Boolean = applySkin(control, textureId, skinId);
					if (bSkinApplied) {
						return true;
					}
					_deferredTextureInfo.push( new DeferredSkinControl( skinControl, controlId, textureId, skinId, index ) );
				}
				return false;
			}

			public function skinDisplayObject( control:DisplayObject, textureId:String, skinId:String = 'texture', index:int = -1):Boolean {
				if ( control ) {
					var bSkinApplied:Boolean = applySkin(control, textureId, skinId);
					if (bSkinApplied) {
						return true;
					}
					_deferredTextureInfo.push( new DeferredSkinDisplayObject( skinDisplayObject, control, textureId, skinId, index ) );
				}
				return false;
			}

			private function applySkin(control:DisplayObject, textureId:String, skinId:String = 'texture'): Boolean {
				var result:Boolean = false;
				var textures:Object;
				if ( control is Button ) {
					textures = getImage( textureId );
				} else {
					textures = getScaleTextures( textureId );
				}
				if ( textures ) {
					control[skinId] = textures;
					result = true;
					CONFIG::DEBUG {
						if ( control[skinId] is Image && control[skinId].texture == _debugTexture ) {
							// what is this case for?
						}
					}
				} else if ( !_applyingDeferredTextures ) {
					result = false;
				}
				return result;
			}

			public function colorControl( controlId:String, textureId:String, index:int = -1, defaultColor:uint = 0xBAADF00D ):Boolean {
				var result:Boolean = false;
				var control:DisplayObject = getControl( controlId, false, index );
				if ( control ) {
					var color:uint = getColor( textureId, defaultColor );
					control['color'] = color;
					if ( color == defaultColor || color == 0 ) {
						_deferredTextureInfo.push( new DeferredColorControl( colorControl, controlId, textureId, index, defaultColor ) );
					} else {
						result = true;
					}
				}
				return result;
			}

			public function colorLabel( controlId:String, textureId:String, index:int = -1, defaultColor:uint = 0xBAADF00D ):Boolean {
				var result:Boolean = false;
				var control:DisplayObject = getControl( controlId, false, index );
				if ( control && control is Label ) {
					var color:uint = getColor( textureId, defaultColor );
					var label:Label = control as Label;
					label.textRendererProperties.textFormat.color = color;
					label.invalidate();
					if ( color == defaultColor || color == 0 ) {
						_deferredTextureInfo.push( new DeferredColorControl( colorLabel, controlId, textureId, index, defaultColor ) );
					} else {
						result = true;
					}
				}
				return result;
			}

			private var _applyingDeferredTextures:Boolean = false;

			public function applyDeferredTextures( resource:IResource ):void {
				_applyingDeferredTextures = true;
				var length:uint = _deferredTextureInfo.length;
				for ( var index:uint = 0; index < length; ++index ) {
					if ( _deferredTextureInfo[index].process() ) {
						_deferredTextureInfo.splice( index, 1 );
						index--;
						length--;
					}
				}
				_applyingDeferredTextures = false;
			}

			private function applyTextures(container:ConfigurableControl):void {
				var control:DisplayObject = getControlForContainer(container);
				_currentControl = control;
				var config:Object = container.config;

				var slider:Slider = control as Slider;
				if (slider) {
					initSlider(slider, config);
					return;
				}

				var button:Button = control as Button;
				if (button) {
					skinButton(button, config);
				} else if (control is PickerList){
					var pickerList:PickerList = control as PickerList;
					skinButton(pickerList.buttonProperties, config["buttonProperties"]);
				} else {
					skinTexture( config, "textureId", control, "texture" );
					skinTexture( config, "textureId", control, "textures" );
					skinTextureAtlas( config, "textureAtlasId", control, "textureAtlas" );
					skinFont( config, "fontId", control, "font" );
				}
				skin( config, "defaultTextureId", control, "defaultSkin" );
				skin( config, "hoverTextureId", control, "hoverSkin" );
				skin( config, "downTextureId", control, "downSkin" );
				skin( config, "disabledTextureId", control, "disabledSkin" );
				skin( config, "defaultSelectedTextureId", control, "defaultSelectedSkin" );
				skin( config, "selectedHoverTextureId", control, "selectedHoverSkin" );
				skin( config, "selectedDownTextureId", control, "selectedDownSkin" );
				skin( config, "selectedDisabledTextureId", control, "selectedDisabledSkin" );
				skin( config, "backgroundTextureId", control, "backgroundSkin" );
				skin( config, "backgroundFocusedTextureId", control, "backgroundFocusedSkin" );
				skin( config, "backgroundDisabledId", control, "backgroundDisabledSkin" );
				skin( config, "onTextureId", control, "onBackground" );
				skin( config, "offTextureId", control, "offBackground" );
				skin( config, "fillTextureId", control, "fillSkin" );

				// Button icons
				if (button) {
					skin( config, "defaultIconId", control, "defaultIcon" );
					skin( config, "defaultSelectedIconId", control, "defaultSelectedIcon" );
					skin( config, "upIconId", control, "upIcon" );
					skin( config, "downIconId", control, "downIcon" );
					skin( config, "hoverIconId", control, "hoverIcon" );
					skin( config, "disabledIconId", control, "disabledIcon" );
					skin( config, "selectedUpIconId", control, "selectedUpIcon" );
					skin( config, "selectedDownIconId", control, "selectedDownIcon" );
					skin( config, "selectedHoverIconId", control, "selectedHoverIcon" );
					skin( config, "selectedDisabledIconId", control, "selectedDisabledIcon" );
					var iconScale:Number = getConfigNumber( config, "iconScale" );
					if (iconScale==iconScale) {
						if (button.defaultIcon != null) { button.defaultIcon.scaleX = button.defaultIcon.scaleY = iconScale; }
						if (button.defaultSelectedIcon != null) { button.defaultSelectedIcon.scaleX = button.defaultSelectedIcon.scaleY = iconScale; }
						if (button.upIcon != null) { button.upIcon.scaleX = button.upIcon.scaleY = iconScale; }
						if (button.downIcon != null) { button.downIcon.scaleX = button.downIcon.scaleY = iconScale; }
						if (button.hoverIcon != null) { button.hoverIcon.scaleX = button.hoverIcon.scaleY = iconScale; }
						if (button.disabledIcon != null) { button.disabledIcon.scaleX = button.disabledIcon.scaleY = iconScale; }
						if (button.selectedUpIcon != null) { button.selectedUpIcon.scaleX = button.selectedUpIcon.scaleY = iconScale; }
						if (button.selectedDownIcon != null) { button.selectedDownIcon.scaleX = button.selectedDownIcon.scaleY = iconScale; }
						if (button.selectedHoverIcon != null) { button.selectedHoverIcon.scaleX = button.selectedHoverIcon.scaleY = iconScale; }
						if (button.selectedDisabledIcon != null) { button.selectedDisabledIcon.scaleX = button.selectedDisabledIcon.scaleY = iconScale; }
					}
				}
			}

			static private var _lookup:Dictionary = new Dictionary();

			private function skinButton( skinnable:Object, config:Object ):Boolean {
				var result:Boolean = false;
				var id:String;
				if (configHasProperty(config,"textureId")) {
					id = getConfigString(config,"textureId");
					skinnable["defaultSkin"] = getImage( id + "_NonFocus" );
					skinnable["hoverSkin"] = skinnable["downSkin"] = getImage( id + "_Selected" );
					var disableImg:DisplayObject = getImage( id + "_Disable" );
					if (disableImg == null) {
						var idx:int = id.indexOf("_");
						if (idx > -1) {
							disableImg = getImage( id.substr(0,idx) + "_Disable" );
						}
					}
					skinnable["disabledSkin"] = disableImg;
				}

				// allow for icon assets named: <ID>_Selected, <ID>_NonFocus, <ID>_Disable
				if (configHasProperty(config,"iconId")) {
					id = getConfigString(config,"iconId");
					var selectedImg:DisplayObject = getImage( id + "_Selected" );
					var nonFocusImg:DisplayObject = getImage( id + "_NonFocus" );
					var disabledImg:DisplayObject = getImage( id + "_Disable" );
					skinnable["defaultIcon"] = (nonFocusImg != null) ? nonFocusImg : selectedImg;
					if (disabledImg != null) {
						skinnable["disabledIcon"] = disabledImg;
					}
					if (selectedImg != null) {
						skinnable["hoverIcon"] = selectedImg;
					}
				}

// TODO: currently only checking to see if the default skin was set.
				if ( skinnable["defaultSkin"] == null && !_applyingDeferredTextures ) {
					_deferredTextureInfo.push( new DeferredSkinButton( skinButton, skinnable, config ) );
				} else if ( skinnable["defaultSkin"] ) {
					result = true;
					CONFIG::DEBUG {
						if ( skinnable["defaultSkin"] is Image && skinnable["defaultSkin"].texture == _debugTexture ) {
							result = false;
						}
					}
				}

				return result;
			}

			private function configHasProperty( config:Object, fieldName:String ):Boolean {
				if ( fieldName in config ) {
					return config[fieldName] !== null;
				}
				var variantFieldName:String;
				var len:int = ACTIVE_VARIANTS.length;
				if (len > 0) {
					for (var i:int=0; i<len; ++i) {
						if ( _lookup[fieldName] != undefined && _lookup[fieldName][i] != undefined ) {
							variantFieldName = _lookup[fieldName][i];
						}
						else {
							variantFieldName = fieldName + ACTIVE_VARIANTS[i];
							if ( _lookup[fieldName] == undefined ) {
								_lookup[fieldName] = new Dictionary();
							}
							_lookup[fieldName][i] = variantFieldName;
						}
						if ( config[variantFieldName] != undefined ) {
							return config[variantFieldName] !== null;
						}
					}
				}
				return false;
			}

			private function getConfig( config:Object, fieldName:String ):Object {
				var value:Object = config[ getConfigFieldName(config,fieldName) ];
				if (value is String) {
					var str:String = value as String;
					if (str.indexOf("{") == 0) {
						value = String(getAsReference(str,null));
					} else if (str.indexOf("(") == 0) {
						value = this.eval( str );
					}
				}
				return value;
			}

			private function getConfigNumber( config:Object, fieldName:String ):Number {
				var result:Number;
				fieldName = getConfigFieldName(config,fieldName);
				var value:* = config[fieldName];
				if (value is String) {
					var str:String = value as String;
					if (str.indexOf("{") == 0) {
						value = getAsReference(str,null);
						result = Number( value );
					} else if (str.indexOf("(") == 0) {
						result = this.eval( str );
					}
				} else {
					result = value == null ? NaN : Number(value);
				}
				return result;
			}

			private function getStringNumber( value:String ):Number {
				var result:Number;
				var str:String = value;
				if ( str && str.indexOf("{") == 0 ) {
					var reference:* = getAsReference( str, null );
					result = reference == null ? NaN : Number( reference ) ;
				} else if ( str && str.indexOf("(") == 0 ) {
					result = this.eval( str );
				} else if ( str && str.indexOf("@(") == 0 ) {
					_bindExpression = str.substring(1);
					result = this.eval( _bindExpression );
					_bindExpression = null;
				} else {
					result = value == null ? NaN : Number( value ) ;
				}
				return result;
			}

			private function getConfigString( config:Object, fieldName:String ):String {
				return config[ getConfigFieldName(config,fieldName) ] as String;
			}

			private static var baseNames:TTLCache = new TTLCache(60*60);

			private function splitDots( value:String ):Vector.<String> {
				var parts:Vector.<String> = baseNames.getItem(value) as Vector.<String>;
				if (parts == null) {
					var startSkip:int=0;
					var endSkip:int=0;
					if (value.indexOf("{") == 0) {
						startSkip = 1;
						endSkip = 1;
					}
					var idx:int = value.indexOf(".");
					var firstPart:String = value;
					if (idx == -1) {
						if (startSkip != 0) {
							firstPart = value.substr(startSkip,value.length-startSkip-endSkip);
						}
						parts = new Vector.<String>(1,true);
						parts[0] = firstPart;
					} else {
						var numDots:int = 1;
						for( var i:int=value.indexOf(".",idx+1); i!=-1; numDots++) {
							i = value.indexOf(".",i+1);
						}
						parts = new Vector.<String>(numDots+1,true);
						i=0;
						while( idx > 0 ) {
							firstPart = value.substr(startSkip,idx-startSkip);
							parts[i++] = firstPart;
							var nextIdx:int = value.indexOf(".",idx+1);
							if (nextIdx == -1) {
								var secondPart:String = value.substr(idx+1,value.length-idx-endSkip-1);
								parts[i++] = secondPart;
								break;
							}
							startSkip = idx+1;
							idx = nextIdx;
						}
					}
					baseNames.putItem(value,parts);
				}
				return parts;
			}

			private function getBaseFieldName( fieldName:String ):String {
				var parts:Vector.<String> = splitDots(fieldName);
				return parts[0];
			}

			private function getVariantName( fieldName:String ):String {
				var parts:Vector.<String> = splitDots(fieldName);
				return parts.length > 1 ? parts[1] : null;
			}

			private function getConfigFieldName( config:Object, fieldName:String ):String {
				var len:int = ACTIVE_VARIANTS.length;
				if (len > 0) {
					var variantName:String;
					for (var i:int=0; i<len; ++i) {
						if ( _lookup[fieldName] != undefined && _lookup[fieldName][i] != undefined ) {
							variantName = _lookup[fieldName][i];
						}
						else {
							variantName = fieldName + ACTIVE_VARIANTS[i];
							if ( _lookup[fieldName] == undefined ) {
								_lookup[fieldName] = new Dictionary();
							}
							_lookup[fieldName][i] = variantName;
						}
						if ( config[variantName] != undefined ) {
							return variantName;
						}
					}
				}
				return fieldName;
			}

			private function checkNumber( n:Number, msg:String ) : Boolean {
				if ( isNaN(n) || !isFinite(n) ) {
					trace("checkNumber: "+msg + " " + n );
					return false;
				}
				return true;
			}

			public function reposition( control:DisplayObject, bottomUp:Boolean = false ):void {
				_controlList.sort( depthSort );
				var len:int = _controlList.length;
				var container:ConfigurableControl;
				var i:int;
				for (i=0; i<len; ++i) {
					if (_controlList[i].id == control.name) {
						break;
					}
				}
				if (i < len) {
					var mainContainer:ConfigurableControl = _controlList[i];
					len = mainContainer.originalNumChildren + 1;
					var j:int;
					if (bottomUp) {
						for (j=len-1; j>=0; --j) {
							container = _controlList[i+j];
							positionAndSizeControl( container, true );
						}
					} else {
						for (j=0; j<len; j++) {
							container = _controlList[i+j];
							positionAndSizeControl( container, true );
						}
					}
				}
			}

			private var _bindExpression:String = null;
			private var _bindings:Dictionary = null;	// context variable name => Vector.<BindingInfo>

			private function doBind( contextNameOrControl:*, expression:String ):void {
				if (_bindings == null) {
					_bindings = new Dictionary();
				}
				var bound:Vector.<BindingInfo> = _bindings[contextNameOrControl];
				if (bound == null) {
					_bindings[contextNameOrControl] = bound = new Vector.<BindingInfo>();
				}
				var current:SerializationStackEntry = _ser.current;
				var found:Boolean = false;
				var info:BindingInfo;
				var len:int = bound.length;
				for (var i:int=0; i<len; i++) {
					info = bound[i];
					if (info.target == current.toObject && info.fieldName == current.fieldKey && info.expression == expression) {
						found = true;
					}
				}
				if (!found) {
					var root:Object = _ser.stack[0].toObject;
					info = new BindingInfo( root, current.toObject, current.fieldKey, expression );
					bound.push( info );
				}
			}
			
			public function hasControlBindings():Boolean {
				if (_bindings) {
					for (var contextNameOrControl:* in _bindings) {
						var control:DisplayObject = contextNameOrControl as DisplayObject;
						if (control) {
							return true;
						}
					}
				}
				return false;
			}

			public function updateControlBindings():void {
				if (_bindings) {
					for (var contextNameOrControl:* in _bindings) {
						var control:DisplayObject = contextNameOrControl as DisplayObject;
						if (control) {
							var bound:Vector.<BindingInfo> = _bindings[control];
							for each (var info:BindingInfo in bound) {
								info.target[info.fieldName] = this.evaluate( info.expression );
							}
						}
					}
				}
			}

			public function removeBindings( control:DisplayObject ):void {
				if (_bindings) {
					var bound:Vector.<BindingInfo> = _bindings[control];
					_removeBindings(bound,null);
					for (var contextNameOrControl:* in _bindings) {
						bound = _bindings[contextNameOrControl];
						_removeBindings(bound,control);
					}
				}
			}
			
			private function _removeBindings( bound:Vector.<BindingInfo>, control:DisplayObject ):void {
				if (bound) {
					var len:int = bound.length;
					for (var i:int=0; i<len; i++) {
						var info:BindingInfo = bound[i];
						if (control == null || info.root == control) {
							info.dispose();
							bound.splice(i--,1);
							len--;
						}
					}
				}
			}

			public function removeAllBindings():void {
				if (_bindings) {
					for (var contextNameOrControl:* in _bindings) {
						var bound:Vector.<BindingInfo> = _bindings[contextNameOrControl];
						var len:int = bound.length;
						for (var i:int=0; i<len; i++) {
							var info:BindingInfo = bound[i];
							info.dispose();
						}
						bound.length = 0;
					}
				}
			}

			private var _triggers:Dictionary = null;	// context variable name => Vector.<TriggerInfo>
			private var _pendingTrigger:TriggerInfo;

			private function hasTrigger( expression:String, func:Function ):Boolean {
				var found:Boolean = false;
				if (_triggers != null) {
					for (var contextName:String in _triggers) {
						if (hasTriggerForContext( contextName, expression, func )) {
							found = true;
							break;
						}
					}
				}
				return found;
			}

			private function hasTriggerForContext( contextName:String, expression:String, func:Function ):Boolean {
				var found:Boolean = false;
				if (_triggers != null) {
					var triggers:Vector.<TriggerInfo> = _triggers[contextName];
					if (triggers) {
						var len:int = triggers.length;
						for (var i:int=0; i<len; i++) {
							if (triggers[i].func == func && triggers[i].expression == expression) {
								found = true;
								break;
							}
						}
					}
				}
				return found;
			}

			private function addContextTriggerForVariable( contextName:String, triggerInfo:TriggerInfo):void {
				if (_triggers == null) {
					_triggers = new Dictionary();
				}
				if (hasTriggerForContext(contextName,triggerInfo.expression,triggerInfo.func)) {
					return;
				}
				var triggers:Vector.<TriggerInfo> = _triggers[contextName];
				if (!triggers) {
					_triggers[contextName] = triggers = new Vector.<TriggerInfo>();
				}
				triggers.push( triggerInfo );
			}

			public function addContextTrigger( expression:String, func:Function, params:Array=null):void {
				if (!hasTrigger(expression,func)){
					_pendingTrigger = new TriggerInfo( expression, func, params );
					eval(expression);
					_pendingTrigger = null;
				}
			}

			public function removeContextTrigger( expression:String, func:Function ):void {
				if (_triggers != null) {
					for (var contextName:String in _triggers) {
						var triggers:Vector.<TriggerInfo> = _triggers[contextName];
						if (triggers) {
							var len:int = triggers.length;
							for (var i:int=0; i<len; i++) {
								var triggerInfo:TriggerInfo = triggers[i];
								if (triggerInfo.func == func && triggerInfo.expression == expression) {
									triggerInfo.dispose();
									triggers.splice(i--,1);
									len--;
								}
							}
						}
					}
				}
			}

			private function stringContextSubstitution( value:String ):String {
				if (value == null) {
					return null;
				}

				if (value.indexOf("@(") == 0) {
					_bindExpression = value.substr(1);
					var newValue:String = evaluate(_bindExpression);
					_bindExpression = null;
					return newValue;
				}

				return LayoutUtil.contextSubstitution(value,_context);
			}

			private function contextSubstitution( container:ConfigurableControl, control:DisplayObject, prop:String ):void {
				var config:Object = container.config;
				if (configHasProperty(config,prop)) {
					var oldValue:String = config[prop];
					var newValue:String = LayoutUtil.contextSubstitution(oldValue,_context);
					if (newValue != oldValue) {
						container.setProperty( control, prop, newValue );
					}
				}
			}

			private function positionAndSizeControl(container:ConfigurableControl, processRelatives:Boolean):void {
				var control:DisplayObject = getControlForContainer(container);
				var controlAsGroup:LayoutGroup = control as LayoutGroup;
				_currentControl = control;
				var config:Object = container.config;

				if (config.hasOwnProperty("context")) {
					var context:Object = config["context"];
					for (var key:String in context) {
						_setContextValue(key,context[key]);
					}
				}

				var parent:DisplayObjectContainer = control.parent;
				if (parent is LayoutViewPort) {
					parent = parent.parent.parent.parent;	// Skip Viewport, Sprite, and Scroller
				}
				var parentGroup:LayoutGroup = parent as LayoutGroup;
				var parentWidth:Number;
				var parentHeight:Number;
				var parentLeft:Number;
				var parentTop:Number;
				var parentRight:Number;
				var parentBottom:Number;
				var pivot:Number = 0;
				var value:Number;

				var percentScale:Number;
				if (configHasProperty(config,"scale")) {
					percentScale = Serialization.getAsPercent( getConfig(config,"scale") );
					if (percentScale!=percentScale) {
						var scale:Number = getConfigNumber(config,"scale");
						container.setProperty( control, "scaleX", scale );
						container.setProperty( control, "scaleY", scale );
					}
				}
				if (configHasProperty(config,"scaleX")) {
					container.setProperty( control, "scaleX", getConfigNumber(config,"scaleX") );
				}
				if (configHasProperty(config,"scaleY")) {
					container.setProperty( control, "scaleY", getConfigNumber(config,"scaleY") );
				}

				if (container.parent) {
					var parentBounds:Rectangle = container.parent.bounds;
					if (parentBounds == null) {
						parentBounds = container.parent.bounds = new Rectangle();
					}
					parent.getBounds( parent, parentBounds );
					parentHeight = parentBounds.height;
					parentWidth = parentBounds.width;
					if (parentGroup) {
						parentHeight -= container.parent.totalChildHeightConcrete + parentGroup.paddingTop + parentGroup.paddingBottom;
						parentWidth -= container.parent.totalChildWidthConcrete + parentGroup.paddingLeft + parentGroup.paddingRight;
						var numChildrenM1:int = parentGroup.numChildren-1;
						if (numChildrenM1 > 0) {
							if (parentGroup.direction == LayoutGroup.DIRECTION_VERTICAL) {
								parentHeight -= numChildrenM1 * parentGroup.gap;
							} else if (parentGroup.direction == LayoutGroup.DIRECTION_HORIZONTAL) {
								parentWidth -= numChildrenM1 * parentGroup.gap;
							}
						}
					}
					parentLeft = parentBounds.left;
					parentTop = parentBounds.top;
					parentRight = parentBounds.right;
					parentBottom = parentBounds.bottom;
				} else {
					parentBottom = parentHeight = ViewportUtil.layoutHeight;
					parentRight = parentWidth = ViewportUtil.layoutWidth;
					parentLeft = 0;
					parentTop = 0;
				}

				control.rotation = 0; // reset back to zero first

				var aspectRatio:Number = getAspectRatio( config );

				var listWidth:Number = getAsPercentX(config,"listWidth",control,container,processRelatives,parentWidth,true);
				if (listWidth==listWidth) { // Not NaN
					container.setProperty( control, "listWidth", listWidth );
				}
				var listHeight:Number = getAsPercentY(config,"listHeight",control,container,processRelatives,parentHeight,true);
				if (listHeight==listHeight) { // Not NaN
					container.setProperty( control, "listHeight", listHeight );
				}
				if (aspectRatio==aspectRatio && ((listHeight==listHeight && listWidth!=listWidth) || (listHeight!=listHeight && listWidth==listWidth))) {
					if (listHeight!=listHeight) {
						listHeight = listWidth * aspectRatio;
					} else {
						listWidth = listHeight / aspectRatio;
					}
				}
				if (listHeight==listHeight) {
					container.setProperty( control, "listHeight", listHeight );
				}
				if (listWidth==listWidth) {
					container.setProperty( control, "listWidth", listWidth );
				}

				var configWidth:Number = getAsPercentX(config,"width",control,container,processRelatives,parentWidth,true);
				//			if (configWidth==configWidth) {	// Not NaN
				//				if (control.scaleX != 1.0 && Serialization.isPercent(getConfig(config,"width")) && (configHasProperty(config,"scale") || configHasProperty(config,"scaleX")) ) {
				//					configWidth /= control.scaleX;
				//				}
				//			}
				var configHeight:Number = getAsPercentY(config,"height",control,container,processRelatives,parentHeight,true);
				//			if (configHeight==configHeight) {	// Not NaN
				//				if (control.scaleY != 1.0 && Serialization.isPercent(getConfig(config,"height")) && (configHasProperty(config,"scale") || configHasProperty(config,"scaleY")) ) {
				//					configHeight /= control.scaleY;
				//				}
				//			}
				if (aspectRatio==aspectRatio && ((configHeight==configHeight && configWidth!=configWidth) || (configHeight!=configHeight && configWidth==configWidth))) {
					if (configHeight!=configHeight) {
						configHeight = configWidth * aspectRatio;
					} else {
						configWidth = configHeight / aspectRatio;
					}
				}
				if (configWidth==configWidth) {
					container.setProperty( control, "width", configWidth );
				}
				if (configHeight==configHeight) {
					container.setProperty( control, "height", configHeight );
				}

				if (percentScale==percentScale && control.width != 0 && control.height != 0) {
					var percentWidth:Number = parentWidth / (control.width / control.scaleX);
					var percentHeight:Number = parentHeight / (control.height / control.scaleY);
					var percentScaleX:Number = percentWidth * percentScale;
					var percentScaleY:Number = percentHeight * percentScale;
					var scaleMode:String;
					if ( configHasProperty(config,"scaleMode") ) {
						scaleMode = getConfigString( config,"scaleMode");
					}
					if ( scaleMode == 'vertical' ) {
						container.setProperty( control, "scaleX", percentScaleY );
						container.setProperty( control, "scaleY", percentScaleY );
					} else if ( scaleMode == 'horizontal' ) {
						container.setProperty( control, "scaleX", percentScaleX );
						container.setProperty( control, "scaleY", percentScaleX );
					} else if ( percentScaleX < percentScaleY ) {
						container.setProperty( control, "scaleX", percentScaleX );
						container.setProperty( control, "scaleY", percentScaleX );
					} else {
						container.setProperty( control, "scaleX", percentScaleY );
						container.setProperty( control, "scaleY", percentScaleY );
					}
				}

				if (container.parent && !processRelatives && parentGroup) {
					if (configHeight!=configHeight && listHeight!=listHeight) {
						container.parent.totalChildHeightConcrete += control.height;
					}
					if (configWidth!=configWidth && listWidth!=listWidth) {
						container.parent.totalChildWidthConcrete += control.width;
					}
				}
				setAsPercentX(config,"minWidth",control,container,processRelatives,parentWidth);
				setAsPercentY(config,"minHeight",control,container,processRelatives,parentHeight);
				setAsPercentX(config,"maxWidth",control,container,processRelatives,parentWidth);
				setAsPercentY(config,"maxHeight",control,container,processRelatives,parentHeight);
				if (controlAsGroup) {
					if (controlAsGroup.direction == LayoutGroup.DIRECTION_HORIZONTAL) {
						setAsPercentX(config,"gap",control,container,processRelatives,parentWidth);
					} else if (controlAsGroup.direction == LayoutGroup.DIRECTION_VERTICAL) {
						setAsPercentY(config,"gap",control,container,processRelatives,parentHeight);
					}
				}
				setAsPercentX(config,"paddingLeft",control,container,processRelatives,parentWidth);
				setAsPercentY(config,"paddingTop",control,container,processRelatives,parentHeight);
				setAsPercentX(config,"paddingRight",control,container,processRelatives,parentWidth);
				setAsPercentY(config,"paddingBottom",control,container,processRelatives,parentHeight);

				var pivotX:Number;
				var pivotY:Number;
				var controlWidth:Number = control.width;
				var controlHeight:Number = control.height;

				if (processRelatives) {
					var width:Number = controlWidth;
					var height:Number = controlHeight;
					if ( control is FeathersControl ) {
						if (control.scaleX < 0) {
							width *= -1;
						}
						if (control.scaleY < 0) {
							height *= -1;
						}
					}
					if (configHasProperty(config,"pivot")) {
						pivot = getConfigNumber(config,"pivot");
						container.setProperty( control, "pivotX", width * pivot / (control.scaleX < 0 ? -control.scaleX : control.scaleX) );
						pivotX = control.pivotX;	// Could have changed in setter
						container.setProperty( control, "pivotY", height * pivot / (control.scaleY < 0 ? -control.scaleY : control.scaleY) );
						pivotY = control.pivotY;
					}

					if (configHasProperty(config, "pivotX")) {
						pivotX = getConfigNumber(config, "pivotX");
						container.setProperty( control, "pivotX", width * pivotX / (control.scaleX < 0 ? -control.scaleX : control.scaleX) );
						pivotX = control.pivotX;
					}

					if (configHasProperty(config, "pivotY")) {
						pivotY = getConfigNumber(config, "pivotY");
						container.setProperty( control, "pivotY", height * pivotY / (control.scaleY < 0 ? -control.scaleY : control.scaleY) );
						pivotY = control.pivotY;
					}
				}

				// Feathers Controls don't report their scaled values.
				var fc:FeathersControl = control as FeathersControl;
				if(fc != null) {
					if (control.scaleX < 0) {
						controlWidth *= -1;
						pivotX *= -1;
					}
					if (control.scaleY < 0) {
						controlHeight *= -1;
						pivotY *= -1;
					}
				}

				var setX:Boolean = false;
				if (configHasProperty(config,"x")) {
					container.setProperty( control, "x", ((parentLeft==parentLeft) ? parentLeft : 0) + getAsPercentX(config,"x",control,container,processRelatives,parentWidth) ); setX = true;
				} else if (configHasProperty(config,"left")) {
					container.setProperty( control, "x", (parentLeft + getAsPercentX(config,"left",control,container,processRelatives,parentWidth) + ((pivotX!=pivotX) ? 0 : pivotX) ) ); setX = true;
					if (configHasProperty(config,"right")) {
						container.setProperty( control, "width", (parentWidth - getAsPercentX(config,"right",control,container,processRelatives,parentWidth) - control.x) );
					}
				} else if (configHasProperty(config,"right")) {
					setX = true;
					if (configHasProperty(config,"x")) {
						container.setProperty( control, "width", (parentWidth - getAsPercentX(config,"right",control,container,processRelatives,parentWidth) - control.x) );
					} else {
						container.setProperty( control, "x", (parentWidth - getAsPercentX(config,"right",control,container,processRelatives,parentWidth) - controlWidth + ((pivotX!=pivotX) ? 0 : pivotX)) );
					}
				} else if (configHasProperty(config,"horizontalCenter")) {
					setX = true;
					if (processRelatives) {
						if ((pivotX!=pivotX)) {
							container.setProperty( control, "x", parentLeft + (parentWidth / 2) + getAsPercentX(config,"horizontalCenter",control,container,processRelatives,parentWidth) - (controlWidth / 2) );
						} else {
							container.setProperty( control, "x", parentLeft + (parentWidth / 2) + getAsPercentX(config,"horizontalCenter",control,container,processRelatives,parentWidth) );
						}
					} else {
						control.x = 0;
					}
				} else if (parentLeft==parentLeft && (parentGroup == null || parentGroup.horizontalAlign == LayoutGroup.HALIGN_NONE || parentGroup.direction == LayoutGroup.DIRECTION_NONE) ) {
					container.setProperty( control, "x", parentLeft ); setX = true;
				}

				var setY:Boolean = false;
				if (configHasProperty(config,"y")) {
					container.setProperty( control, "y", ((parentTop==parentTop) ? parentTop : 0) + getAsPercentY(config,"y",control,container,processRelatives,parentHeight) ); setY = true;
				} else if (configHasProperty(config,"top")) {
					container.setProperty( control, "y", (parentTop + getAsPercentY(config,"top",control,container,processRelatives,parentHeight) + ((pivotY!=pivotY) ? 0 : pivotY) ) ); setY = true;
					if (configHasProperty(config,"bottom")) {
						container.setProperty( control, "height", (parentHeight - getAsPercentY(config,"bottom",control,container,processRelatives,parentHeight) - control.y) );
					}
				} else if (configHasProperty(config,"bottom")) {
					setY = true;
					if (configHasProperty(config,"y")) {
						container.setProperty( control, "height", (parentHeight - getAsPercentY(config,"bottom",control,container,processRelatives,parentHeight) - control.y) );
					} else {
						container.setProperty( control, "y", (parentHeight - getAsPercentY(config,"bottom",control,container,processRelatives,parentHeight) - controlHeight + ((pivotY!=pivotY) ? 0 : pivotY)) );
					}
				} else if (configHasProperty(config,"verticalCenter")) {
					setY = true;
					if (processRelatives) {
						if ((pivotY!=pivotY)) {
							container.setProperty( control, "y", parentTop + (parentHeight / 2) + getAsPercentY(config,"verticalCenter",control,container,processRelatives,parentHeight) - (controlHeight / 2) );
						} else {
							container.setProperty( control, "y", parentTop + (parentHeight / 2) + getAsPercentY(config,"verticalCenter",control,container,processRelatives,parentHeight) );
						}
					} else {
						control.y = 0;
					}
				} else if (parentTop==parentTop && (parentGroup == null || parentGroup.verticalAlign == LayoutGroup.VALIGN_NONE || parentGroup.direction == LayoutGroup.DIRECTION_NONE) ) {
					container.setProperty( control, "y", parentTop ); setY = true;
				}

				if (parentGroup && parentGroup.direction == LayoutGroup.DIRECTION_NONE) {
					container.setProperty( control, "x", setX ? (control.x + parentGroup.paddingLeft) : parentGroup.paddingLeft );
					container.setProperty( control, "y", setY ? (control.y + parentGroup.paddingTop) : parentGroup.paddingTop );
				}

				if (configHasProperty(config,"rotation")) {
					container.setProperty( control, "rotation", getConfigNumber(config,"rotation") );
				}

				if (processRelatives && control.hasOwnProperty("textureScale") && configHasProperty(config, "textureScale")) {
					container.setProperty( control, "textureScale", getConfigNumber(config,"textureScale") );
				}

				if (fc != null) {
					if (!processRelatives) {
						fc.invalidate(FeathersControl.INVALIDATION_FLAG_SIZE);
					} else {
						fc.invalidate(FeathersControl.INVALIDATION_FLAG_SIZE);
						fc.invalidate(FeathersControl.INVALIDATION_FLAG_STYLES);
					}
				}

				CONFIG::DEBUG {
					if (configHasProperty(config,"debug")) {
						if (control && parent) {
							trace(control.name,
								"x:"+String(Math.round(control.x*100.0)/100.0),
								"y:"+String(Math.round(control.y*100.0)/100.0),
								"w:"+String(Math.round(control.width*100.0)/100.0),
								"h:"+String(Math.round(control.height*100.0)/100.0),
								"pw:"+String(Math.round(parent.width*100.0)/100.0),
								"ph:"+String(Math.round(parent.height*100.0)/100.0) );
						}
						if (processRelatives) {
							makeDebugHighlight( control, config["debug"] );
						}
					}
				}

					_currentControl = null;
			}

			private function getAspectRatio(config:Object):Number {
				var desiredAspectRatio:Number;
				var value:* = getConfig(config,"aspectRatio");
				if (value != null && value != undefined) {
					var w:Number;
					var h:Number;
					if (value is Number || value is int) {
						desiredAspectRatio = Number(value);
					} else {
						var str:String = String(value);
						var sep:int = str.indexOf("x");
						if (sep == -1) {
							throw new Error("aspectRatio string values must be of the form \"WxH\" where W and H are numbers representing width and height.");
						}
						w = Number(str.substr(0,sep));
						h = Number(str.substr(sep+1));
						desiredAspectRatio = h / w;
					}
				}
				return desiredAspectRatio;
			}

			CONFIG::DEBUG {

				private function makeDebugHighlight( control:DisplayObject, colorValue:String ):void {
					var color:uint = uint(colorValue);
					if (colorValue.indexOf("0x") != 0) {
						color = uint(colors[colorValue]);
					}
					const thickness:int = 2;

					var bounds:Rectangle;
					if ( control.stage == null ) {
						bounds = new Rectangle();
					} else {
						bounds = control.getBounds( control.stage );
					}

					var left:Quad = new Quad( thickness, thickness, color );
					var right:Quad = new Quad( thickness, thickness, color );
					var top:Quad = new Quad( thickness, thickness, color );
					var bottom:Quad = new Quad( thickness, thickness, color );
					var pivot1:Quad = new Quad( thickness, thickness * 3, color);
					var pivot2:Quad = new Quad( thickness * 3, thickness, color);

					var sprite:Sprite = new Sprite();
					sprite.touchable = false;
					sprite.addChild( left );
					sprite.addChild( right );
					sprite.addChild( top );
					sprite.addChild( bottom );
					sprite.addChild( pivot1 );
					sprite.addChild( pivot2 );

					// special clipRect quad
					if ( control is FeathersControl ) {
						var clipRect:Rectangle = ( control as FeathersControl ).clipRect;
						if ( clipRect ) {
							var clipQuad:Quad = new Quad( clipRect.width, clipRect.height, color );
							clipQuad.alpha = 0.2;
							sprite.addChild( clipQuad );
						}
					}

					Starling.current.stage.addChild( sprite );
					if (debugHighlights == null) {
						debugHighlights = new Dictionary(true);
						updateDebugTimer = ProcessManager.instance.timedCallNamed( updateDebugHighlights, 0.1, "ViewLayoutDebugHighlits");
					} else {
						removeDebugHighlight(control);
					}
					debugHighlights[sprite] = control;
					if (control.name) {
						sprite.name = "Debug_"+control.name;
					} else {
						sprite.name = "Debug_"+String(numDebugHighlights);
					}
					sprite.name += " "+DebugUtils.memoryLocation(sprite);
					updateDebugQuad(sprite,control);
				}

				private function get numDebugHighlights():int {
					var count:int = 0;
					for (var key:* in debugHighlights) {
						count++;
					}
					return count;
				}

				private function updateDebugQuad( sprite:Sprite, control:DisplayObject):void {
					if ( control.stage != null ) {
						const thickness:int = 2;
						var bounds:Rectangle = control.getBounds( control.stage );

						var matrix:Matrix = control.getTransformationMatrix(control.stage);
						MatrixUtil.prependScale( matrix, 1/control.scaleX, 1/control.scaleY );
						sprite.transformationMatrix = matrix;

						var left:Quad = sprite.getChildAt(0) as Quad;
						left.height = control.height;
						var right:Quad = sprite.getChildAt(1) as Quad;
						right.height = control.height;
						right.x = control.width - thickness;
						var top:Quad = sprite.getChildAt(2) as Quad;
						top.width = control.width;
						var bottom:Quad = sprite.getChildAt(3) as Quad;
						bottom.width = control.width;
						bottom.y = control.height - thickness;

						var pivot1:Quad = sprite.getChildAt(4) as Quad;
						var pivot2:Quad = sprite.getChildAt(5) as Quad;
						var pivotX:Number = control.pivotX;
						var pivotY:Number = control.pivotY;
						if ( control is FeathersControl ) {
							pivotX *= control.scaleX;
							pivotY *= control.scaleY;
						}
						pivot1.x = pivotX - (pivot1.width / 2);
						pivot1.y = pivotY - (pivot1.height / 2);
						pivot2.x = pivotX - (pivot2.width / 2);
						pivot2.y = pivotY - (pivot2.height / 2);

						// special clipRect quad
						if ( control is FeathersControl && sprite.numChildren >= 6 ) {
							var clipRect:Rectangle = ( control as FeathersControl ).clipRect;
							if ( clipRect ) {
								var clipQuad:Quad = sprite.getChildAt(6) as Quad;
								if (clipQuad) {
									clipQuad.x = clipRect.x;
									clipQuad.y = clipRect.y;
								}
							}
						}
					}
				}

				private function updateDebugHighlights():void {
					for (var key:* in debugHighlights) {
						var sprite:Sprite = key as Sprite;
						var control:DisplayObject = debugHighlights[key] as DisplayObject;
						updateDebugQuad( sprite, control );
					}
				}

				private function removeDebugHighlights():void {
					for (var key:* in debugHighlights) {
						var sprite:Sprite = key as Sprite;
						sprite.removeFromParent(true);
					}
					ProcessManager.instance.remove( updateDebugTimer );
					debugHighlights = null;
				}

				private function removeDebugHighlight(control:DisplayObject):void {
					if (debugHighlights) {
						for (var key:* in debugHighlights) {
							var sprite:Sprite = key as Sprite;
							if (debugHighlights[key] == control) {
								sprite.removeFromParent(true);
								delete debugHighlights[key];
							}
						}
					}
				}

			} // END CONFIG::DEBUG

				public function lookup(variable:String):* {
					if (variable.indexOf("'")==0 || variable.indexOf('"')==0) {
						return variable.substr(1,variable.length-2);
					} else {
						var result:* = getAsReference(variable,null);
						if ( result == null ) {
							// check experiment tags, return Boolean: true if tag present, false if not.
							if ( _contextTags ) {
								result = Boolean( _contextTags.indexOf( variable ) != -1 );
							}
						}
						return result;
					}
				}

				private static const HELPER_RECTANGLE:Rectangle = new Rectangle();

			private function checkPendingBinding( value:String ):void {
				if (_bindExpression != null) {
					doBind(value,_bindExpression);
				}
				if (_pendingTrigger != null) {
					addContextTriggerForVariable(value,_pendingTrigger);
				}
			}

			static private var totalScaleX:Number;
			static private var totalScaleY:Number;
			private function refreshTotalScale(target:DisplayObject):void {
				if (target == null) {
					totalScaleX = totalScaleY = 1.0;
				} else {
					var scaleX:Number = target.scaleX;
					var scaleY:Number = target.scaleY;
					var p:DisplayObjectContainer = target.parent;
					while (p) {
						scaleX *= p.scaleX;
						scaleY *= p.scaleY;
						p = p.parent;
					}
					totalScaleX = scaleX;
					totalScaleY = scaleY;
				}
			}

			private function getAsReference( value:String, target:DisplayObject ):Object {
				var result:*;
				if (target == null) {
					target = _currentControl;
				}

				var originalValue:String = value;
				var name:String = value;
				var dot:int = value.indexOf(".");
				var parts:Vector.<String> = null;
				if (dot != -1) {
					parts = splitDots( value );
					name = parts[0];
				}

				if (_context[value] != undefined) {
					checkPendingBinding( value );
					result = _context[value];
				} else if (_contextValues[value] != undefined) {
					checkPendingBinding( value );
					result = _contextValues[value];
				} else if (value == "totalScaleX") {
					refreshTotalScale(target);
					result = totalScaleX;
				} else if (value == "totalScaleY") {
					refreshTotalScale(target);
					result = totalScaleY;
				} else if (value == "{layout.width}" || value == "layout.width") {
					result = ViewportUtil.layoutWidth;
				} else if (value == "{layout.height}" || value == "layout.height") {
					result = ViewportUtil.layoutHeight;
				} else if (value == "groupIndex") {
					result = getControlGroupIndex(target);
				} else {
					if (dot == -1) {
						checkPendingBinding( value ); // Could be a future binding?
						result = 0;
					} else {
						var partIndex:int = 1;
						var field:String = parts[partIndex];
						var source:Object;
						source = getDataModel(name);
						var fromDataModel:Boolean = (source != null);
						var isMagic:Boolean = false;
						if (!fromDataModel) {
							if (name == "parent") {
								isMagic = true;
								if (target) {
									source = target.parent;
								}
							} else if (target && name == "this") {
								isMagic = true;
								if (target) {
									source = target;
								}
							} else if (target && name == "view") {
								isMagic = true;
								if (target) {
									source = BaseView.getViewForControl(target);
								}
							}
							if (!isMagic && source == null) {
								source = getControl(name,_layoutPhase < 1);
							}
						}
						if (source == null && !isMagic) {
							// It's not a control or a data model, so
							// check for bindings whether or not we find a value currently in the view context
							checkPendingBinding(name);

							source = getContextValue(name);
							if (source && (Serialization.isPrimitiveValue(source) || !source.hasOwnProperty(field))) {
								source = null;
							}
						}
						if (source != null) {
							if ( source.hasOwnProperty(field) ) {
								result = source[field];
								if (++partIndex < parts.length) {
									field = parts[partIndex];
									result = result[field];
								}
							}
							var control:DisplayObject = source as DisplayObject;
							if (control && result == undefined) {
								result = getDisplayObjectField( control, field );
							}
							if (control && _bindExpression != null) {
								doBind(control,_bindExpression);
							}
							if ( fromDataModel && !(result is Number || result is int || result is uint) ) {
								result = Number( result );
							}
						}
					}
				}
				return result;
			}


			private function getDisplayObjectField( control:DisplayObject, field:String ):* {
				var result:*;
				if (field=="left") {
					result = control.x;
				} else if (field=="top") {
					result = control.y;
				} else if (field=="bottom" || field=="right") {
					control.getBounds(control,HELPER_RECTANGLE);
					if (field=="bottom") {
						result = HELPER_RECTANGLE.bottom;
					} else {
						result = HELPER_RECTANGLE.right;
					}
				} else if (field=="scale") {
					result = control.scaleX;
				} else if (field=="pivot") {
					result = control.width != 0 ? (control.pivotX / control.width) : control.pivotX;
				} else if (field=="groupIndex") {
					result = getControlGroupIndex(control);
				}
				return result;
			}

			private function eval(expression:String):* {
				var postfixExpr:Array;
				if (_expressions[expression] != undefined) {
					postfixExpr = _expressions[expression];
				} else {
					var parserExp:Array = _evaluator.simpleParser.parse(expression, _evaluator);
					postfixExpr = _evaluator.converter.convert(parserExp, 0, parserExp.length);
					_expressions[expression] = postfixExpr;
				}
				var result:* = _evaluator.calculator.eval(postfixExpr, 0, postfixExpr.length, _evaluator);
				return result;
			}

			public function evaluate( value:* ): * {
				var result:* = value;
				if (value is String) {
					var str:String = value as String;
					if (str.indexOf("{") == 0) {
						value = getAsReference(str,null);
					} else if (str.indexOf("(") == 0) {
						result = this.eval( str );
					} else if (str.indexOf("@(") == 0) {
						_bindExpression = str.substring(1);
						result = this.eval( _bindExpression );
						_bindExpression = null;
					} else {
						var percentage:Number = Serialization.getAsPercent(value);
						if ( percentage==percentage ) {
							result = percentage;
						}
					}
				}
				return result;
			}

			private function getAsPercentX(config:Object, fieldName:String, control:DisplayObject, container:ConfigurableControl, processRelatives:Boolean, max:Number, isWidth:Boolean = false):Number {
				var result:Number;
				var percentage:Number;
				var value:Object;
				var configFieldName:String = getConfigFieldName(config,fieldName);
				if (configFieldName in config && (value = config[configFieldName]) !== null) {
					var str:String = value as String;
					if (str && str.indexOf("{") == 0) {
						value = getAsReference(str,control);
						result = Number( value );
						if (isWidth && container.parent && !processRelatives) {
							container.parent.totalChildWidthConcrete += result;
						}
					} else if (str && str.indexOf("(") == 0) {
						result = this.eval( str );
						if (isWidth && container.parent && !processRelatives) {
							container.parent.totalChildWidthConcrete += result;
						}
					} else if (str && str.indexOf("in") != -1) {
						result = inchesToPixels(str);
						if (isWidth && container.parent && !processRelatives) {
							container.parent.totalChildWidthConcrete += result;
						}
					} else {
						percentage = Serialization.getAsPercent(value);
						if ( percentage!=percentage ) {
							result = Number( value );
							if (isWidth && container.parent && !processRelatives) {
								container.parent.totalChildWidthConcrete += result;
							}
						} else {
							var ratio:Number = container.parent ? container.parent.totalChildWidthPercentage : 1;
							if (ratio > 1) {
								result = max * percentage * (1.0 / ratio);
							} else {
								result = max * percentage;
							}
							if (isWidth && container.parent && !processRelatives && container.parent.controlIsLayoutGroup && container.parent.direction != LayoutGroup.DIRECTION_NONE) {
								container.parent.totalChildWidthPercentage += percentage;
							}
							if (result == Number.POSITIVE_INFINITY || result == Number.NEGATIVE_INFINITY || result!=result) {
								result = 0;
							}
						}
					}
				}
				return result;
			}

			private function inchesToPixels(value:String):Number {
				var result:Number;
				var idx:int = value.indexOf("in");
				if (idx > 0) {
					result = Number(value.substr(0,idx));
					result *= LayoutUtil.deviceDpi;
				}
				return result;
			}

			private function getAsPercentY(config:Object, fieldName:String, control:DisplayObject, container:ConfigurableControl, processRelatives:Boolean, max:Number, isHeight:Boolean = false):Number {
				var result:Number;
				var percentage:Number;
				var value:Object;
				var configFieldName:String = getConfigFieldName(config,fieldName);
				if (configFieldName in config && (value = config[configFieldName]) !== null) {
					var str:String = value as String;
					if (str && str.indexOf("{") == 0) {
						value = getAsReference(str,control);
						result = Number( value );
						if (isHeight && container.parent && !processRelatives) {
							container.parent.totalChildHeightConcrete += result;
						}
					} else if (str && str.indexOf("(") == 0) {
						result = this.eval( str );
						if (isHeight && container.parent && !processRelatives) {
							container.parent.totalChildHeightConcrete += result;
						}
					} else if (str && str.indexOf("in") != -1) {
						result = inchesToPixels(str);
						if (isHeight && container.parent && !processRelatives) {
							container.parent.totalChildHeightConcrete += result;
						}
					} else {
						percentage = Serialization.getAsPercent(value);
						if ( percentage != percentage ) {
							result = Number( value );
							if (isHeight && container.parent && !processRelatives) {
								container.parent.totalChildHeightConcrete += result;
							}
						} else {
							var ratio:Number = container.parent ? container.parent.totalChildHeightPercentage : 1;
							if (ratio > 1) {
								result = max * percentage * (1.0 / ratio);
							} else {
								result = max * percentage;
							}
							if (isHeight && container.parent && !processRelatives && container.parent.controlIsLayoutGroup && container.parent.direction != LayoutGroup.DIRECTION_NONE) {
								container.parent.totalChildHeightPercentage += percentage;
							}
							if (result == Number.POSITIVE_INFINITY || result == Number.NEGATIVE_INFINITY || result!=result) {
								result = 0;
							}
						}
					}
				}
				return result;
			}

			private function setAsPercentX(config:Object, fieldName:String, control:DisplayObject, container:ConfigurableControl, processRelatives:Boolean, max:Number, isWidth:Boolean = false):Number {
				var value:Number = getAsPercentX(config,fieldName,control,container,processRelatives,max,isWidth);
				if (value==value) {	// Not NaN
					control[fieldName] = value
				}
				return value;
			}

			private function setAsPercentY(config:Object, fieldName:String, control:DisplayObject, container:ConfigurableControl, processRelatives:Boolean, max:Number, isHeight:Boolean = false):Number {
				var value:Number = getAsPercentY(config,fieldName,control,container,processRelatives,max,isHeight);
				if (value==value) {	// Not NaN
					control[fieldName] = value
				}
				return value;
			}

			private function initSlider(slider:Slider, config:Object):void
			{
				skin( config, "defaultTextureId", slider.thumbProperties, "defaultSkin" );
				skin( config, "hoverTextureId", slider.thumbProperties, "hoverSkin" );
				skin( config, "downTextureId", slider.thumbProperties, "downSkin" );
				skin( config, "disabledTextureId", slider.thumbProperties, "disabledSkin" );

				if (configHasProperty(config,"thumbWidth")) {
					slider.thumbProperties.width = getConfigNumber(config,"thumbWidth");
				}

				if (configHasProperty(config,"thumbHeight")) {
					slider.thumbProperties.height = getConfigNumber(config,"thumbWidth");
				}
				if (configHasProperty(config,"minimumTrackTextureId")) {
					slider.minimumTrackProperties.defaultSkin = GraphicsUtil.createImage( getTexture( getConfigString(config,"minimumTrackTextureId") ) );
				}
			}

			protected function skin(config:Object, configField:String, control:Object, controlField:String):Boolean {
				var result:Boolean = false;
				if ( configHasProperty(config,configField) && controlField in control ) {
					var id:String = getConfigString(config,configField);
					if (id != "" && id != "null") {
						id = LayoutUtil.contextSubstitution(id,_context);
						control[controlField] = getImage(id);
						if ( control[controlField] == null && !_applyingDeferredTextures ) {
							_deferredTextureInfo.push( new DeferredSkin( this.skin, config, configField, control, controlField ) );
						} else {
							result = true;
							CONFIG::DEBUG {
								if ( control[controlField] is Image && control[controlField].texture == _debugTexture ) {
									result = false;
								}
							}
						}
					} else {
						control[controlField] = null;
					}
				}
				return result;
			}

			protected function skinTextureAtlas(config:Object, configField:String, control:Object, controlField:String):Boolean {
				var result:Boolean = false;
				if ( configHasProperty(config,configField) && controlField in control ) {
					var id:String = config[configField];
					if (id != "" && id != "null") {
						id = LayoutUtil.contextSubstitution(id,_context);
						var textureAtlas:TextureAtlas = getTextureAtlas( id );
						if ( textureAtlas ) {
							CONFIG::RELEASE {
								try {
									control[controlField] = textureAtlas;
									result = true;
								} catch (e:Error) {
									// Wrong type of texture?  i.e. Scale9 vs. Texture
									result = false;
								}
							}
							CONFIG::DEBUG {
//								try {
									control[controlField] = textureAtlas;
									result = true;
//								} catch (e:Error) {
//									trace("Control '"+control.toString()+"' had wrong texture '"+id+"' for field '"+controlField+"' '"+controlField+"'");
//									throw e;
//								}
							}
						} else if ( control[controlField] == null && !_applyingDeferredTextures ) {
							_deferredTextureInfo.push( new DeferredSkin( this.skinTextureAtlas, config, configField, control, controlField ) );
						}
					} else {
						control[controlField] = null;
					}
				}
				return result;
			}

			protected function skinTexture(config:Object, configField:String, control:Object, controlField:String):Boolean {
				var result:Boolean;
				if ( configHasProperty(config,configField) && control.hasOwnProperty(controlField) ) {
					var id:String = getConfigString( config, configField );
					if (id != "" && id != "null") {
						id = LayoutUtil.contextSubstitution(id,_context);
						var texture:Object = getScaleTextures( id );
						if ( texture ) {
							CONFIG::RELEASE {
								try {
									control[controlField] = texture;
									result = true;
									if ( control is BCGTiledImage ) {
										( control as BCGTiledImage ).deferredTexture = false;
									}
								} catch (e:Error) {
									// Wrong type of texture?  i.e. Scale9 vs. Texture
									result = false;
								}
							}
							CONFIG::DEBUG {
								try {
									control[controlField] = texture;
									result = true;
									if ( control is BCGTiledImage ) {
										( control as BCGTiledImage ).deferredTexture = false;
									}
								} catch (e:Error) {
									trace("Control '"+control.toString()+"' had wrong texture '"+id+"' for field '"+controlField+"' '"+controlField+"'");
									result = false;
									throw e;
								}
							}
						} else if ( !_applyingDeferredTextures ) {
							_deferredTextureInfo.push( new DeferredSkin( this.skinTexture, config, configField, control, controlField ) );
							if ( control is BCGTiledImage ) {
								( control as BCGTiledImage ).deferredTexture = true;
							}
						}
					} else {
						control[controlField] = null;
					}
				}
				return result;
			}

			protected function skinFont(config:Object, configField:String, control:Object, controlField:String):Boolean {
				var result:Boolean = false;
				if ( configHasProperty(config,configField) && control.hasOwnProperty(controlField) ) {
					var id:String = config[configField];
					if (id != "" && id != "null") {
						id = LayoutUtil.contextSubstitution(id, _context);
						var resource:BitmapFontResource = getResource( id ) as BitmapFontResource;
						if ( resource ) {
							var font:BitmapFont = resource.bitmapFont;
							if ( font ) {
								control[controlField] = font;
								result = true;
							} else if ( !_applyingDeferredTextures ) {
								_deferredTextureInfo.push( new DeferredSkin( this.skinFont, config, configField, control, controlField ) );
							}
						} else if ( !_applyingDeferredTextures ) {
							_deferredTextureInfo.push( new DeferredSkin( this.skinFont, config, configField, control, controlField ) );
						}
					} else {
						control[controlField] = null;
					}
				}
				return result;
			}

			private function parseSound( data:Object ):void {
				if (data.hasOwnProperty("sound") == false) {
					return;
				}

				var soundData:Object = data["sound"];
				if (soundData.hasOwnProperty("soundList") == false) {
					return;
				}

				var soundList:Object = soundData["soundList"];
				for each (var sound:Object in soundList) {
					if ( sound ) {
						var url:String = LayoutUtil.contextSubstitution(sound["url"], _context);
						sound["url"] = url;
					}
				}
			}

			private function parseAssets( data:Object, resourceBundle:ResourceBundle ):void {
				if (data.hasOwnProperty("assets")) {
					var assetData:Object = data["assets"];
					var assetArray:Array = assetData as Array;
					if (assetArray) {
						var length:uint = assetArray.length;
						if (length > 0) {
							for ( var index:uint = 0; index < length; ++index ) {
								LayoutUtil.collectTextureReferences( _viewFilename, assetArray[index], _resourceManager, resourceBundle, _context, true, null, collectTexturesDeferrable );
							}
						}
					} else {
						for (var name:String in assetData) {
							var asset:Object = assetData[name];
							var url:String = LayoutUtil.contextSubstitution(asset["url"], _context);

							switch( asset["asset"] ) {
								case "textureAtlas":
									resourceBundle.addTextureAtlas( name, url,
										asset.hasOwnProperty("ttl") ? asset["ttl"] : -1,
										asset.hasOwnProperty("properties") ? asset["properties"] : null,
										null, null,
										asset.hasOwnProperty("decorate") ? asset["decorate"] : true,
										asset.hasOwnProperty("priority") ? asset["priority"] : ResourceManager.PRIORITY_NORMAL,
										asset.hasOwnProperty("deferrable") ? asset["deferrable"] : true );
									break;
								case "resource":
									var type:Type = Type.forName(asset["type"]);
									resourceBundle.addResource( name, url, type.clazz,
										asset.hasOwnProperty("ttl") ? asset["ttl"] : -1,
										asset.hasOwnProperty("properties") ? asset["properties"] : null,
										null, null,
										asset.hasOwnProperty("decorate") ? asset["decorate"] : true,
										asset.hasOwnProperty("priority") ? asset["priority"] : ResourceManager.PRIORITY_NORMAL,
										asset.hasOwnProperty("deferrable") ? asset["deferrable"] : true );
									break;
								case null:
									resourceBundle.removeResource( name );
									break;
								default:
									throw new Error("As yet unsupported asset resource type: "+asset["asset"]);
							}
						}
					}
				}
			}

			public function hasStyle( styleName:String ):Boolean {
				var data:Object = null;
				if (_styles) {
					return _styles[styleName] != undefined;
				}
				return false;
			}

			public function hasHelp():Boolean
			{
				if(_help && _help.length > 0)
				{
					return true;
				}
				return false;
			}

			public function getHelp():Vector.<Object>
			{
				return _help;
			}

			public function getStyleNames():Vector.<String> {
				var result:Vector.<String> = new Vector.<String>();
				for (var name:String in _styles) {
					result.push(name);
				}
				result.sort(0);
				return result;
			}

			public function getAnimationNames():Vector.<String> {
				var result:Vector.<String> = new Vector.<String>();
				for each (var name:String in _animationManager.animationNames()) {
					result.push(name);
				}
				result.sort(0);
				return result;
			}

			public function getStyleData( styleName:String ):Object {
				var data:Object = null;
				if (_styles) {
					data = _styles[styleName] as Object;
				}
				if (data == null) {
					throw new Error("Style not found: "+styleName);
				}
				return data;
			}

			private function createDataModels( layoutData:Object, resourceBundle:ResourceBundle ):void {
				var newDataModels:Dictionary = new Dictionary();
				if ( layoutData.hasOwnProperty( "data" ) ) {
					try {
						_ser.filter = evaluate;
						var dataModels:Object = layoutData["data"];
						for ( var id:String in dataModels ) {
							var data:Object = dataModels[id];
							LayoutUtil.collectTextureReferences( _viewFilename, data, _resourceManager, resourceBundle, _context, true, null, collectTexturesDeferrable );
							var typeName:String = data["_type"];
							var dataModelType:Type = Type.forName( typeName );
							var iDataModel:IDataModel = _dataModels[id];
							if ( iDataModel ) {
								if ( iDataModel is dataModelType.clazz ) {
									_ser.copyFields( data, iDataModel );
									newDataModels[id] = iDataModel;
								} else {
									iDataModel = null;
								}
							}
							if ( !iDataModel ) {
								iDataModel = _ser.fromObject( data, dataModelType ) as IDataModel;
								newDataModels[id] = iDataModel;
							}
						}
					} catch( e:Error ) {
						_consoleModel.logError( "ViewLayout::createDataModels() " + e.message);
						_consoleModel.logError( e.getStackTrace());
					}
					_ser.filter = null;
				}
				_dataModels = newDataModels;
			}

			public function getDataModel( id:String ):IDataModel {
				return _dataModels[id];
			}

			public function reLayoutWithResourceBundle( resourceBundle:ResourceBundle ): void {

				_resourceBundles.unshift( resourceBundle );

				layoutPhase0(_controlList);

				for each ( var control:ConfigurableControl in _controlList ) {
					positionAndSizeControl(control, false);
				}
				for each ( control in _controlList ) {
					positionAndSizeControl( control, true);
				}
			}

			public function reLayoutWithoutResourceBundle( resourceBundle:ResourceBundle ): void {

				var idx:int = _resourceBundles.indexOf( resourceBundle );
				if ( idx >= 0 ) {
					_resourceBundles.splice( idx, 1 );

					layoutPhase0(_controlList);

					for each ( var control:ConfigurableControl in _controlList ) {
						positionAndSizeControl(control, false);
					}
					for each ( control in _controlList ) {
						positionAndSizeControl(control, true);
					}
				}
			}

			public function onViewRemovedFromStage(): void {
				CONFIG::DEBUG {
					removeDebugHighlights();
				}
			}

			public function get context():Dictionary {
				return _context;
			}

			static private var _curlyKeys:TTLCache = new TTLCache(60*60);

			private function makeCurlyKey(key:String):String {
				var curlyKey:String = key;
				if (key.indexOf("{")!=0) {
					curlyKey = _curlyKeys.getItem(key) as String;
					if (!curlyKey) {
						curlyKey = "{"+key+"}";
						_curlyKeys.putItem(key,curlyKey);
					}
				}
				return curlyKey;
			}

			static private var _unCurlyKeys:TTLCache = new TTLCache(60*60);

			private function makeUnCurlyKey(key:String):String {
				var unCurlyKey:String = key;
				if (key.indexOf("{")==0) {
					unCurlyKey = _unCurlyKeys.getItem(key) as String;
					if (!unCurlyKey) {
						unCurlyKey = key.substr(1,key.length-2);
						_unCurlyKeys.putItem(key,unCurlyKey);
					}
				}
				return unCurlyKey;
			}

			CONFIG::DEBUG {
				private static var colors:Object = {
					"AliceBlue": 0xF0F8FF, "aliceblue": 0xf0f8ff,
					"AntiqueWhite": 0xFAEBD7, "antiquewhite": 0xfaebd7,
					"Aqua": 0x00FFFF, "aqua": 0x00ffff,
					"Aquamarine": 0x7FFFD4, "aquamarine": 0x7fffd4,
					"Azure": 0xF0FFFF, "azure": 0xf0ffff,
					"Beige": 0xF5F5DC, "beige": 0xf5f5dc,
					"Bisque": 0xFFE4C4, "bisque": 0xffe4c4,
					"Black": 0x000000, "black": 0x000000,
					"BlanchedAlmond": 0xFFEBCD, "blanchedalmond": 0xffebcd,
					"Blue": 0x0000FF, "blue": 0x0000ff,
					"BlueViolet": 0x8A2BE2, "blueviolet": 0x8a2be2,
					"Brown": 0xA52A2A, "brown": 0xa52a2a,
					"BurlyWood": 0xDEB887, "burlywood": 0xdeb887,
					"CadetBlue": 0x5F9EA0, "cadetblue": 0x5f9ea0,
					"Chartreuse": 0x7FFF00, "chartreuse": 0x7fff00,
					"Chocolate": 0xD2691E, "chocolate": 0xd2691e,
					"Coral": 0xFF7F50, "coral": 0xff7f50,
					"CornflowerBlue": 0x6495ED, "cornflowerblue": 0x6495ed,
					"Cornsilk": 0xFFF8DC, "cornsilk": 0xfff8dc,
					"Crimson": 0xDC143C, "crimson": 0xdc143c,
					"Cyan": 0x00FFFF, "cyan": 0x00ffff,
					"DarkBlue": 0x00008B, "darkblue": 0x00008b,
					"DarkCyan": 0x008B8B, "darkcyan": 0x008b8b,
					"DarkGoldenRod": 0xB8860B, "darkgoldenrod": 0xb8860b,
					"DarkGray": 0xA9A9A9, "darkgray": 0xa9a9a9,
					"DarkGreen": 0x006400, "darkgreen": 0x006400,
					"DarkKhaki": 0xBDB76B, "darkkhaki": 0xbdb76b,
					"DarkMagenta": 0x8B008B, "darkmagenta": 0x8b008b,
					"DarkOliveGreen": 0x556B2F, "darkolivegreen": 0x556b2f,
					"DarkOrange": 0xFF8C00, "darkorange": 0xff8c00,
					"DarkOrchid": 0x9932CC, "darkorchid": 0x9932cc,
					"DarkRed": 0x8B0000, "darkred": 0x8b0000,
					"DarkSalmon": 0xE9967A, "darksalmon": 0xe9967a,
					"DarkSeaGreen": 0x8FBC8F, "darkseagreen": 0x8fbc8f,
					"DarkSlateBlue": 0x483D8B, "darkslateblue": 0x483d8b,
					"DarkSlateGray": 0x2F4F4F, "darkslategray": 0x2f4f4f,
					"DarkTurquoise": 0x00CED1, "darkturquoise": 0x00ced1,
					"DarkViolet": 0x9400D3, "darkviolet": 0x9400d3,
					"DeepPink": 0xFF1493, "deeppink": 0xff1493,
					"DeepSkyBlue": 0x00BFFF, "deepskyblue": 0x00bfff,
					"DimGray": 0x696969, "dimgray": 0x696969,
					"DodgerBlue": 0x1E90FF, "dodgerblue": 0x1e90ff,
					"FireBrick": 0xB22222, "firebrick": 0xb22222,
					"FloralWhite": 0xFFFAF0, "floralwhite": 0xfffaf0,
					"ForestGreen": 0x228B22, "forestgreen": 0x228b22,
					"Fuchsia": 0xFF00FF, "fuchsia": 0xff00ff,
					"Gainsboro": 0xDCDCDC, "gainsboro": 0xdcdcdc,
					"GhostWhite": 0xF8F8FF, "ghostwhite": 0xf8f8ff,
					"Gold": 0xFFD700, "gold": 0xffd700,
					"GoldenRod": 0xDAA520, "goldenrod": 0xdaa520,
					"Gray": 0x808080, "gray": 0x808080,
					"Green": 0x008000, "green": 0x008000,
					"GreenYellow": 0xADFF2F, "greenyellow": 0xadff2f,
					"HoneyDew": 0xF0FFF0, "honeydew": 0xf0fff0,
					"HotPink": 0xFF69B4, "hotpink": 0xff69b4,
					"IndianRed": 0xCD5C5C, "indianred": 0xcd5c5c,
					"Indigo": 0x4B0082, "indigo": 0x4b0082,
					"Ivory": 0xFFFFF0, "ivory": 0xfffff0,
					"Khaki": 0xF0E68C, "khaki": 0xf0e68c,
					"Lavender": 0xE6E6FA, "lavender": 0xe6e6fa,
					"LavenderBlush": 0xFFF0F5, "lavenderblush": 0xfff0f5,
					"LawnGreen": 0x7CFC00, "lawngreen": 0x7cfc00,
					"LemonChiffon": 0xFFFACD, "lemonchiffon": 0xfffacd,
					"LightBlue": 0xADD8E6, "lightblue": 0xadd8e6,
					"LightCoral": 0xF08080, "lightcoral": 0xf08080,
					"LightCyan": 0xE0FFFF, "lightcyan": 0xe0ffff,
					"LightGoldenRodYellow": 0xFAFAD2, "lightgoldenrodyellow": 0xfafad2,
					"LightGray": 0xD3D3D3, "lightgray": 0xd3d3d3,
					"LightGreen": 0x90EE90, "lightgreen": 0x90ee90,
					"LightPink": 0xFFB6C1, "lightpink": 0xffb6c1,
					"LightSalmon": 0xFFA07A, "lightsalmon": 0xffa07a,
					"LightSeaGreen": 0x20B2AA, "lightseagreen": 0x20b2aa,
					"LightSkyBlue": 0x87CEFA, "lightskyblue": 0x87cefa,
					"LightSlateGray": 0x778899, "lightslategray": 0x778899,
					"LightSteelBlue": 0xB0C4DE, "lightsteelblue": 0xb0c4de,
					"LightYellow": 0xFFFFE0, "lightyellow": 0xffffe0,
					"Lime": 0x00FF00, "lime": 0x00ff00,
					"LimeGreen": 0x32CD32, "limegreen": 0x32cd32,
					"Linen": 0xFAF0E6, "linen": 0xfaf0e6,
					"Magenta": 0xFF00FF, "magenta": 0xff00ff,
					"Maroon": 0x800000, "maroon": 0x800000,
					"MediumAquaMarine": 0x66CDAA, "mediumaquamarine": 0x66cdaa,
					"MediumBlue": 0x0000CD, "mediumblue": 0x0000cd,
					"MediumOrchid": 0xBA55D3, "mediumorchid": 0xba55d3,
					"MediumPurple": 0x9370DB, "mediumpurple": 0x9370db,
					"MediumSeaGreen": 0x3CB371, "mediumseagreen": 0x3cb371,
					"MediumSlateBlue": 0x7B68EE, "mediumslateblue": 0x7b68ee,
					"MediumSpringGreen": 0x00FA9A, "mediumspringgreen": 0x00fa9a,
					"MediumTurquoise": 0x48D1CC, "mediumturquoise": 0x48d1cc,
					"MediumVioletRed": 0xC71585, "mediumvioletred": 0xc71585,
					"MidnightBlue": 0x191970, "midnightblue": 0x191970,
					"MintCream": 0xF5FFFA, "mintcream": 0xf5fffa,
					"MistyRose": 0xFFE4E1, "mistyrose": 0xffe4e1,
					"Moccasin": 0xFFE4B5, "moccasin": 0xffe4b5,
					"NavajoWhite": 0xFFDEAD, "navajowhite": 0xffdead,
					"Navy": 0x000080, "navy": 0x000080,
					"OldLace": 0xFDF5E6, "oldlace": 0xfdf5e6,
					"Olive": 0x808000, "olive": 0x808000,
					"OliveDrab": 0x6B8E23, "olivedrab": 0x6b8e23,
					"Orange": 0xFFA500, "orange": 0xffa500,
					"OrangeRed": 0xFF4500, "orangered": 0xff4500,
					"Orchid": 0xDA70D6, "orchid": 0xda70d6,
					"PaleGoldenRod": 0xEEE8AA, "palegoldenrod": 0xeee8aa,
					"PaleGreen": 0x98FB98, "palegreen": 0x98fb98,
					"PaleTurquoise": 0xAFEEEE, "paleturquoise": 0xafeeee,
					"PaleVioletRed": 0xDB7093, "palevioletred": 0xdb7093,
					"PapayaWhip": 0xFFEFD5, "papayawhip": 0xffefd5,
					"PeachPuff": 0xFFDAB9, "peachpuff": 0xffdab9,
					"Peru": 0xCD853F, "peru": 0xcd853f,
					"Pink": 0xFFC0CB, "pink": 0xffc0cb,
					"Plum": 0xDDA0DD, "plum": 0xdda0dd,
					"PowderBlue": 0xB0E0E6, "powderblue": 0xb0e0e6,
					"Purple": 0x800080, "purple": 0x800080,
					"Red": 0xFF0000, "red": 0xff0000,
					"RosyBrown": 0xBC8F8F, "rosybrown": 0xbc8f8f,
					"RoyalBlue": 0x4169E1, "royalblue": 0x4169e1,
					"SaddleBrown": 0x8B4513, "saddlebrown": 0x8b4513,
					"Salmon": 0xFA8072, "salmon": 0xfa8072,
					"SandyBrown": 0xF4A460, "sandybrown": 0xf4a460,
					"SeaGreen": 0x2E8B57, "seagreen": 0x2e8b57,
					"SeaShell": 0xFFF5EE, "seashell": 0xfff5ee,
					"Sienna": 0xA0522D, "sienna": 0xa0522d,
					"Silver": 0xC0C0C0, "silver": 0xc0c0c0,
					"SkyBlue": 0x87CEEB, "skyblue": 0x87ceeb,
					"SlateBlue": 0x6A5ACD, "slateblue": 0x6a5acd,
					"SlateGray": 0x708090, "slategray": 0x708090,
					"Snow": 0xFFFAFA, "snow": 0xfffafa,
					"SpringGreen": 0x00FF7F, "springgreen": 0x00ff7f,
					"SteelBlue": 0x4682B4, "steelblue": 0x4682b4,
					"Tan": 0xD2B48C, "tan": 0xd2b48c,
					"Teal": 0x008080, "teal": 0x008080,
					"Thistle": 0xD8BFD8, "thistle": 0xd8bfd8,
					"Tomato": 0xFF6347, "tomato": 0xff6347,
					"Turquoise": 0x40E0D0, "turquoise": 0x40e0d0,
					"Violet": 0xEE82EE, "violet": 0xee82ee,
					"Wheat": 0xF5DEB3, "wheat": 0xf5deb3,
					"White": 0xFFFFFF, "white": 0xffffff,
					"WhiteSmoke": 0xF5F5F5, "whitesmoke": 0xf5f5f5,
					"Yellow": 0xFFFF00, "yellow": 0xffff00,
					"YellowGreen": 0x9ACD32, "yellowgreen": 0x9acd32
				}
			}
		}
}
import starling.display.DisplayObject;

internal class BindingInfo {
	public function BindingInfo( root:Object, target:Object, fieldName:String, expression:String ) {
		this.root = root;
		this.target = target;
		this.fieldName = fieldName;
		this.expression = expression;
	}
	public function dispose():void {
		root = null;
		target = null;
	}
	public var root:Object;
	public var target:Object;
	public var fieldName:String;
	public var expression:String;
}

internal class TriggerInfo {
	public function TriggerInfo( expression:String, func:Function, params:Array=null ) {
		this.func = func;
		this.expression = expression;
		this.params = params;
	}
	public function dispose():void {
		func = null;
		params = null;
	}
	public var func:Function;
	public var expression:String;
	public var params:Array;
}

internal class DeferredTextureInfo {
	protected var func:Function;
	public function DeferredTextureInfo( func:Function ) {
		this.func = func;
	}
	public function process():Boolean { return true; }
}

internal class DeferredSkin extends DeferredTextureInfo {
	protected var config:Object;
	protected var configField:String;
	protected var control:Object;
	protected var controlField:String;
	public function DeferredSkin( func:Function, config:Object, configField:String, control:Object, controlField:String ) {
		super( func );
		this.config = config;
		this.configField = configField;
		this.control = control;
		this.controlField = controlField;
	}
	override public function process():Boolean {
		return this.func( config, configField, control, controlField );
	}
}

internal class DeferredSkinControl extends DeferredTextureInfo {
	protected var controlId:String;
	protected var textureId:String;
	protected var skinId:String;
	protected var index:int;
	public function DeferredSkinControl( func:Function, controlId:String, textureId:String, skinId:String = 'texture', index:int = -1 ) {
		super( func );
		this.controlId = controlId;
		this.textureId = textureId;
		this.skinId = skinId;
		this.index = index;
	}
	override public function process():Boolean {
		return this.func( controlId, textureId, skinId, index );
	}
}

internal class DeferredSkinDisplayObject extends DeferredTextureInfo {
	protected var textureId:String;
	protected var skinId:String;
	protected var index:int;
	protected var dispObject:DisplayObject;
	public function DeferredSkinDisplayObject( func:Function, dispObject:DisplayObject, textureId:String, skinId:String = 'texture', index:int = -1 ) {
		super( func );
		this.dispObject = dispObject;
		this.textureId = textureId;
		this.skinId = skinId;
		this.index = index;
	}
	override public function process():Boolean {
		return this.func( dispObject, textureId, skinId, index );
	}
}

internal class DeferredSkinButton extends DeferredTextureInfo {
	protected var skinnable:Object;
	protected var config:Object;
	public function DeferredSkinButton( func:Function, skinnable:Object, config:Object ) {
		super(func);
		this.skinnable = skinnable;
		this.config = config;
	}
	override public function process():Boolean {
		return this.func( skinnable, config );
	}
}

internal class DeferredColorControl extends DeferredTextureInfo {
	protected var controlId:String;
	protected var textureId:String;
	protected var index:int;
	protected var defaultColor:uint;
	public function DeferredColorControl( func:Function, controlId:String, textureId:String, index:int = -1, defaultColor:uint = 0xBAADF00D ) {
		super(func);
		this.controlId = controlId;
		this.textureId = textureId;
		this.index = index;
		this.defaultColor = defaultColor;
	}
	override public function process():Boolean {
		return this.func( controlId, textureId, index, defaultColor );
	}
}