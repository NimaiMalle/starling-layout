package ui.controls
{
	import com.greensock.core.Animation;
	
	import flash.geom.Point;
	import flash.utils.Dictionary;
	
	import animations.AnimationManager;
	import animations.util.AnimationUtil;
	
	import feathers.core.FeathersControl;
	
	import model.ConsoleModel;
	
	import processes.BaseProcessManager;
	import processes.ProcessManager;
	
	import starling.animation.DelayedCall;
	import starling.display.DisplayObject;
	import starling.display.DisplayObjectContainer;
	import starling.events.Event;
	import starling.events.Touch;
	import starling.events.TouchEvent;
	import starling.events.TouchPhase;
	
	import util.BCGError;
	import util.IEvaluator;
	import util.Serialization;
	
	import view.BaseView;

	public class AnimatedDisplayObjectContainer extends FeathersControl implements IEvaluator
	{
		protected static var _ser:Serialization = new Serialization(false,true);
		
		public var startPlaying:String;
		private var _when:String;

		private var _data:Object = null;
		private var whens:Dictionary;
		private var animationManager:AnimationManager = new AnimationManager();
		private var tweens:Dictionary = new Dictionary();
		private var tweenIds:Dictionary = new Dictionary();
		private var playing:Vector.<String> = new Vector.<String>();
		private var _processManager:BaseProcessManager;
		private var instanceId:uint = 0;		
		private static var nextId:uint = 0;
		private var _view:BaseView;
		private var _delay:DelayedCall;
		private var cacheable:Boolean = true;
		private var expressionCache:Dictionary = new Dictionary();	// This is not just an optimization.  It makes sure that context changes during an animation don't change the value of an expression.

		public function AnimatedDisplayObjectContainer() {
			instanceId = ++nextId;
			this.addEventListener(Event.ADDED_TO_STAGE, addedToStageHandler);
			this.addEventListener(Event.REMOVED_FROM_STAGE, removedFromStageHandler);
		}

		public function get when():String { return _when; }
		public function set when(value:String):void {
			_when = value;
			initializeTriggers();
		}

		override public function dispose():void
		{
			stopAll();
			processManagerName = null;
			if(parent) {
				parent.removeChild(this);
			}
			dispatchEvent(new Event(Event.REMOVE_FROM_JUGGLER));

			this.removeEventListener(Event.ADDED_TO_STAGE, addedToStageHandler);
			this.removeEventListener(Event.REMOVED_FROM_STAGE, removedFromStageHandler);
			
			removeTriggers();
			
			super.dispose();
		}

		protected function initializeTriggers():void {
			removeTriggers();
			if (_view) {
				if (this.whens) {
					for (var animationName:String in this.whens) {
						var expression:String = this.whens[animationName];
						var idx:int = expression.indexOf(".touch")
						if (idx > 0) {
							var targetName:String = expression.substring(0,idx);
							var target:DisplayObject = DisplayObject( getControl(targetName) );
							if (target) {
								if (whenParams==null) {
									whenParams = new Dictionary(true);
								}
								whenParams[target] = animationName;
								CONFIG::DEBUG {
									var parent:DisplayObject = target;
									while (parent) {
										if (parent.touchable == false) {
											ConsoleModel.instance.logError("Control '"+parent.name+"' not touchable in when expression: "+expression);
										}
										parent = parent.parent;
									}
								}
								_view.listenerManager.addEventListener( target, TouchEvent.TOUCH, whenTouched );
							} else {
								ConsoleModel.instance.logError("Target for 'when' not found: "+expression);
							}
						} else {
							var stopCurrent:Boolean = animationManager.getAnimation(animationName).stopCurrent;
							_view.layout.addContextTrigger( expression, this.play, [animationName, stopCurrent] );
						}
					}
				}
			}
		}

		private var whenParams:Dictionary;

		private function whenTouched( event:TouchEvent ):void {
			var target:DisplayObject = event.currentTarget as DisplayObject;
			var touch:Touch = event.getTouch( target, TouchPhase.ENDED );
			if (touch) {
				var params:String = whenParams[target];
				if (params) {
					this.play(params);
				} else {
					ConsoleModel.instance.logError("Target params not found in whenTouched");
				}
			}
		}

		protected function removeTriggers():void {
			if (_view) {
				_view.layout.removeBindings(this);
				if (this.whens) {
					for (var animationName:String in this.whens) {
						var expression:String = this.whens[animationName];
						_view.layout.removeContextTrigger( expression, this.play );
					}
				}
			}
		}

		protected function addedToStageHandler(event:Event):void {
			if(event.target != this) {
				return;
			}

			var newView:BaseView = findView();
			if (_view != newView) {
				_view = newView;
				if(this.name == 'playerProfileParent'){
					trace('duhhhhhh');
				}
				initializeTriggers();
			}
			
			if (animationManager.isInitialized == false && _data != null) {
				animationManager.clear();
				animationManager.initialize( _data, this );
			}
			if (_processManager == null) {
				_processManager = ProcessManager.instance;
			}
			if (startPlaying) {
				_delay = _processManager.delayCallFrames( play, 3, startPlaying ); // Wait three frames for layout completion
			}
		}

		protected function removedFromStageHandler(event:Event):void {
			if(event.target != this) {
				return;
			}
			stopAll();
		}

		public function set animation(data:Object):void {
			if (_view != null) {
				animationManager.clear();
				for (var name:String in data) {
					var animData:Object = data[name];
					if(this.name == 'playerProfileParent' ){
						trace('remove');
					}
					if (animData.hasOwnProperty("when")) {
						var expression:String = animData["when"];
						if (this.whens == null) {
							this.whens = new Dictionary();
						}
						this.whens[name] = expression;
					}
				}
				animationManager.initialize( data, _view.layout );
				initializeTriggers();
			}
			this._data = data;
		}

		public function set processManagerName(value:String):void {
			var oldProcessManager:BaseProcessManager = _processManager;
			_processManager = AnimationUtil.getProcessManager(value, this);
		}

		public function get processManagerName():String {
			return ProcessManager.instance.getMiniProcessManagerId( _processManager );
		}

		public function move( controlId:String, toControlId:String ):void {
			var control:DisplayObject = DisplayObject( getControl( controlId ) );
			var toControl:DisplayObject = DisplayObject( getControl( toControlId ) );
			AnimationUtil.moveTo( control, toControl, false );
		}		
		
		// mostly a wrapper for DisplayObjectContainer's addChild, but also allows object to maintain its world position
		public function AdoptChild(szParent:String, szChild:String, bMaintainPosition:Boolean = true):DisplayObject
		{
			var pParent:DisplayObjectContainer = DisplayObjectContainer( getControl(szParent) );
			var pChild:DisplayObjectContainer = DisplayObjectContainer( getControl(szChild) );
			if (pParent != null && pChild != null) {
				
				// store off global position if desired
				var helperPoint:Point = new Point();
				if (bMaintainPosition) {
					helperPoint.setTo( pChild.x, pChild.y );
					pChild.localToGlobal( helperPoint, helperPoint );
				}
				
				// call DisplayObjectContainer.addChild, which will remove the pChild from the original parent
				pParent.addChild(pChild);
				
				// apply original position if desired
				if (bMaintainPosition) {
					pChild.globalToLocal( helperPoint, helperPoint );
					pChild.x = helperPoint.x;
					pChild.y = helperPoint.y;
				}
			}
			else {
				trace("AdoptChild(" + szParent + ", " + szChild + ") failed!");
				trace("... pParent: " + pParent + ", pChild: " + pChild);
			}	
			return pChild;
		}

		public function arcTo( controlId:String, toControlId:String, duration:Number,
							   vars:Object=null,
							   curvePercent:Number = 0.5,
							   curvePercentVariance:Number = 0.1,
							   initialAngleOffset:Number = 0.0,
							   initialAngleVariance:Number = 1.5,
							   autoRotate:Boolean = false):void {
			var control:DisplayObject = DisplayObject( getControl( controlId ) );
			var toControl:DisplayObject = DisplayObject( getControl( toControlId ) );
			var anim:Animation = AnimationUtil.arcToOther( control, toControl, duration, vars, null,
				curvePercent, curvePercentVariance, initialAngleOffset, initialAngleVariance, autoRotate );
			control.visible = true;
			_processManager.addUntrackedTween( anim );
		}
		
		public function arcFrom( controlId:String, fromControlId:String, duration:Number,
							   vars:Object=null,
							   curvePercent:Number = 0.5,
							   curvePercentVariance:Number = 0.1,
							   initialAngleOffset:Number = 0.0,
							   initialAngleVariance:Number = 1.5,
							   autoRotate:Boolean = false):void {
			var control:DisplayObject = DisplayObject( getControl( controlId ) );
			var fromControl:DisplayObject = DisplayObject( getControl( fromControlId ) );
			var anim:Animation = AnimationUtil.arcFromOther( control, fromControl, duration, vars, null,
				curvePercent, curvePercentVariance, initialAngleOffset, initialAngleVariance, autoRotate );
			_processManager.addUntrackedTween( anim );
			if (control.visible == false) {
				_processManager.delayCallFrames( function():void { control.visible = true; }, 1 );
			}
		}
		
		private function getControl( controlId:String ):Object {
			var control:Object = null;
			if (this.parent != null) {	// If not disposed and completing tweens...
				if (controlId != null) {
					var index:int = -1;
					var bracket:int = controlId.indexOf("[");
					if (bracket != -1) {
						var indexStr:String = controlId.substring(bracket+1,controlId.length-1);
						var indexNum:Number = Number(indexStr);
						if (indexNum!=indexNum) {
							if (this.expressionCache[indexStr] != undefined) {
								indexNum = this.expressionCache[indexStr];
							} else {
								indexNum = Number(_view.layout.evaluate(indexStr));
								this.expressionCache[indexStr] = indexNum;
							}
							this.cacheable = false;
						}
						if (indexNum==indexNum) {
							controlId = controlId.substr(0,bracket);
							index = int(indexNum);
						}
					}
					control = this.getChildByNameR(controlId,index);
					if (!control) {
						control = _view.layout.getDataModel(controlId);
					}
					if (!control) {
						control = _view.layout.getControl(controlId,false,index);
					}
					if (control == null) {
						throw new Error("ADOC named '"+this.name+"' could not find a child or other control named '"+controlId+"' index "+String(index));
					}
				}
			}
			return control;
		}
		
		public function setContext( context:Object ):void {
			_view.layout.setContextValues( context );
		}
		
		public function broadcastContext( name:String ):void {
			_view.layout.broadcastContextValue( name );
		}
		
		public function instantiateStyle( style:String, context:Object=null, onTopOfControlId:String=null ):void {
			var onTopOfControl:DisplayObject = DisplayObject( getControl( onTopOfControlId ) );
			var control:DisplayObject = _view.layout.instantiateStyle( style, onTopOfControl ? onTopOfControl.parent : this, _view.resourceBundle, context );
			if (onTopOfControl) {
				control.x = onTopOfControl.x;
				control.y = onTopOfControl.y;
				control.rotation = onTopOfControl.rotation;
			}
		}
		
		public function modifyControl( controlId:String, properties:Object ):void{
			var control:DisplayObject = DisplayObject( getControl( controlId ) );
			_view.layout.ser.copyFields( properties, control );
		}

		private function findView():BaseView {
			var p:DisplayObjectContainer = this.parent;
			while (p != null && !(p is BaseView)) {
				p = p.parent;
			}
			return p as BaseView;
		}

		public function playAll():void {
			for (var i:int = 0; i<numChildren; i++) {
				AnimationUtil.animate( this.getChildAt(i), null, null, true );
			}
		}

		private function clearExpressionCache():void {
			for (var key:String in this.expressionCache) {
				delete this.expressionCache[key];
			}
		}
		
		public function play(animationName:String, stopCurrent:Boolean=true, vars:Object = null ):void {
			try {
				_delay = null;				
				
				if (_processManager == null || this.stage == null) {
					return;
				}

				// do any evaluating?
				if (animationName.indexOf("(") == 0) {
					animationName = _view.layout.evaluate( animationName );
				}				
				
				if (animationName == null) {
					animationName = animationManager.defaultAnimation;
					if (animationName == null) {
						return;
					}
				}
				var tween:Animation = tweens[animationName];
				var tweenId:String = tweenIds[animationName];
				clearExpressionCache();
				if (!tween) {
					if (vars == null || vars.hasOwnProperty("onComplete") == false) {
						if (vars == null) {
							vars = {};
						}
						vars["onComplete"] = onComplete;
					}
					this.cacheable = true;	// Will get set to false if any expression evaluation is used to get tween targets
					tween = animationManager.create( animationName, getControl, vars, this );
					if (this.cacheable) {
						tweens[animationName] = tween;
					}
					if (!tweenId) {
						tweenId = animationName+String(instanceId);
						tweenIds[animationName] = tweenId;
					}
					tweenIds[animationName] = tweenId;
				} else {
					_processManager.killTween( tweenId );
				}
				_processManager.addTween( tweenId, tween );
				if (stopCurrent) {
					stopAll();
				}
				var index:int = playing.indexOf(animationName);
				if (index >= 0) {
					_processManager.completeTween(tweenId);
				} else {
					index = playing.indexOf(null);
					if (index == -1) {
						index = playing.length;
					}
					playing[index] = animationName;
				}
				if (tween == null) {
					throw new Error("No animation named "+animationName+" found in "+this.name);
				}
				tween.restart( true );
			} catch (e:Error) {
				throw new BCGError(e.message,{"code":e.errorID,"animation_name":animationName,"ADOC_name":this.name,"animation_manager":String(animationManager),"process_manager":String(_processManager)});
			}
		}
		
		public function instantiateAnimatedChild( styleName:String, animation:String ): void {
			var parent:DisplayObjectContainer;
			parent = this;
			
			var child:AnimatedDisplayObjectContainer = _view.instantiateStyle( styleName, parent, false ) as AnimatedDisplayObjectContainer;
			child.play(animation);
		}

		public function onComplete():void {
			this.dispatchEvent( new Event(Event.COMPLETE) );
		}

		public function stop( animationName:String = null ):void {
			if (animationName == null) {
				stopAll();
			} else {
				var index:int = playing.indexOf(animationName);
				if (index >= 0) {
					var tweenId:String = tweenIds[animationName];
					_processManager.completeTween(tweenId);
					playing[index] = null;
				}
			}
		}
		
		public function isPlaying( animationName:String = null ):Boolean {
			if (animationName == null) {
				for (var i:Number = 0; i<playing.length; i++) {
					if (playing[i] != null) 
						return true;
				}
				return false;
			}
			return (playing.indexOf(animationName) >= 0);
		}

		private function stopAll():void {
			if (_processManager) {
				var playingLength:int = playing.length;
				for (var index:int=0; index<playingLength; index++) {
					var current:String = playing[index];
					if (current) {
						var tweenId:String = tweenIds[current];
						_processManager.completeTween( tweenId );
						playing[index] = null;
					}
				}
				if (_delay) {
					_processManager.remove(_delay);
				}
			}
//			for (var i:int = 0; i<numChildren; i++) {
//				AnimationUtil.stop( this.getChildAt(i) );
//			}
		}

		public function getChildByNameR(name:String,index:int=0):DisplayObject {
			var result:DisplayObject = BaseView.findChildByNameR( name, this, index );
			return result;
		}

		public function animationNames():Vector.<String> {
			return animationManager.animationNames();
		}

		public function hasAnimation(name:String):Boolean {
			if (name != null) {
				return animationManager.hasAnimation(name);
			} else {
				return animationManager.numAnimations > 0;
			}
		}

		// Returns a primitive value unchanged, looks up the value of a variable, or evaluates a mathematical or logical expression
		public function evaluate(value:*):* {
			var result:* = _view.layout.evaluate(value);
			if (result != value) {
				this.cacheable = false;
			}
			return result;
		}
		
		// Sets the value of a variable.  The value will be evaluated if it's a string, and the final value is returned
		public function setVariable(name:String,value:*):* {
			return _view.layout.setVariable( name, value );
		}
		
		public function getVariables():Dictionary {
			return _view.layout.getVariables();
		}
	}
}