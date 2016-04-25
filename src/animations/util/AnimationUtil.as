package animations.util {
	
	import com.greensock.TimelineLite;
	import com.greensock.TimelineMax;
	import com.greensock.TweenAlign;
	import com.greensock.TweenLite;
	import com.greensock.TweenMax;
	import com.greensock.core.Animation;
	
	import flash.geom.Point;
	
	import feathers.core.FeathersControl;
	
	import processes.BaseProcessManager;
	import processes.ProcessManager;
	
	import starling.display.DisplayObject;
	import starling.display.DisplayObjectContainer;
	import starling.events.Event;
	
	import ui.controls.AnimatedDisplayObjectContainer;
	import ui.controls.BCGMovieClip;
	import ui.controls.BCGParticleSystem;
	import ui.controls.BCGSpine;
	
	import view.BaseView;
	
	public class AnimationUtil {

		static private var HELPER_POINT_1:Point = new Point();
		static private var HELPER_POINT_2:Point = new Point();

		/**
		 * Start animating anything, recursively
		 * target: The object to start animating.
		 * animation: Optional name of animation to start (only makes sense for some types)
		 * onComplete: Optional callback function when done animating (doesn't make sense if "all" is true)
		 * all: Don't stop at the first animatable object found - animate them all
		 */
		static public function animate( target:Object, animation:String = null, onComplete:Function = null, all:Boolean = false, __animated:Boolean = false ):Boolean {
			if (all == true && onComplete != null) {
				throw new Error( "Can't play multiple animations an supply an onComplete callback function.");
			}
			if (target != null) {
				var asADOC:AnimatedDisplayObjectContainer = target as AnimatedDisplayObjectContainer;
				if ( asADOC ) {
					if (animation != null && asADOC.hasAnimation(animation)) {
						asADOC.play( animation, true, {"onComplete":onComplete} );
						__animated = true;
					}
				}

				var asSpine:BCGSpine = target as BCGSpine;
				if( asSpine ){
					if (asSpine.hasAnimation(animation)) {
						if (onComplete) {
							asSpine.state.onComplete.add(onComplete);
						}
						asSpine.playAnimation( animation );
						return true;
					}
				}

				var asMovieClip:BCGMovieClip = target as BCGMovieClip;
				if (asMovieClip) {
					if (onComplete) {
						asMovieClip.addEventListener( Event.COMPLETE, onComplete );
					}
					asMovieClip.currentFrame = 0;
					asMovieClip.play();
					return true;
				}
				
				var asParticle:BCGParticleSystem = target as BCGParticleSystem;
				if (asParticle) {
					if (onComplete) {
						asParticle.addEventListener( Event.COMPLETE, onComplete );
					}
					asParticle.start();
					return true;
				}

				var asDOC:DisplayObjectContainer = target as DisplayObjectContainer;
				// NOTE!  Chris Wingler changed this on 2015-11-24 to address the case where she had:
				// an AnimatedDisplayObjectContainer parent that had an animation called "clearTheBoard" and
				// AnimatedDisplayObjectContainer children that did NOT have an animation called "clearTheBoard" and
				// supplied an onComplete function ... originally, since the children did NOT have an animation of
				// that same name, it called the onComplete function immediately (which was undesired)
				// TODO: Bill!  Research these animation calls.  Alternatively, Chris can revert this change
				// and add a dummy "clearTheBoard" animation to the children
				//if ( asDOC ) { 
				if ( asDOC || (asDOC && all) ) {
					var length:int = asDOC.numChildren;
					for ( var index:int = 0; index < length; ++index ) {
						__animated = animate( asDOC.getChildAt( index ), animation, onComplete, all, __animated );
						if (!all && __animated) {
							return true;
						}
					}
				}				
			}
			if (!__animated && onComplete) {
				onComplete();
			}
			return __animated;
		}
		
		static public function stop( target:Object ): void {
			if (target != null) {
				
				var asADOC:AnimatedDisplayObjectContainer = target as AnimatedDisplayObjectContainer;
				if ( asADOC ) {
					asADOC.stop();
				}
				
				var asSpine:BCGSpine = target as BCGSpine;
				if( asSpine ){
					asSpine.stop();
				}
				
				var asMovieClip:BCGMovieClip = target as BCGMovieClip;
				if (asMovieClip) {
					asMovieClip.currentFrame = 0;
					asMovieClip.stop();
				}
				
				var asParticle:BCGParticleSystem = target as BCGParticleSystem;
				if (asParticle) {
					asParticle.stop();
				}
				
				var asDOC:DisplayObjectContainer = target as DisplayObjectContainer;
				if ( asDOC ) {
					var length:int = asDOC.numChildren;
					for ( var index:int = 0; index < length; ++index ) {
						stop( asDOC.getChildAt( index ) );
					}
				}
			}			
		}

		static public function arcToOther( target:DisplayObject, to:DisplayObject, duration:Number,
										   vars:Object,
										   onUpdate:Function = null,
										   curvePercent:Number = 0.5,
										   curvePercentVariance:Number = 0.1,
										   initialAngleOffset:Number = 0.0,
										   initialAngleVariance:Number = 1.5,
										   autoRotate:Boolean = false ):Animation {
			HELPER_POINT_1.setTo( to.x, to.y );
			to.parent.localToGlobal( HELPER_POINT_1, HELPER_POINT_1 );
			target.parent.globalToLocal( HELPER_POINT_1, HELPER_POINT_1 );
			return arcTo( target, duration, target.x, target.y, HELPER_POINT_1.x, HELPER_POINT_1.y,
				vars, onUpdate, curvePercent, curvePercentVariance, initialAngleOffset, initialAngleVariance, autoRotate );				
		}
		
		static public function arcFromOther( target:DisplayObject, from:DisplayObject, duration:Number,
										   vars:Object,
										   onUpdate:Function = null,
										   curvePercent:Number = 0.5,
										   curvePercentVariance:Number = 0.1,
										   initialAngleOffset:Number = 0.0,
										   initialAngleVariance:Number = 1.5,
										   autoRotate:Boolean = false ):Animation {
			HELPER_POINT_1.setTo( from.x, from.y );
			from.parent.localToGlobal( HELPER_POINT_1, HELPER_POINT_1 );
			target.parent.globalToLocal( HELPER_POINT_1, HELPER_POINT_1 );
			return arcTo( target, duration, HELPER_POINT_1.x, HELPER_POINT_1.y, target.x, target.y,
				vars, onUpdate, curvePercent, curvePercentVariance, initialAngleOffset, initialAngleVariance, autoRotate );				
		}
		
		static public function doSineWave(target:Object, duration:Number, 
										  startX:Number, startY:Number, endX:Number, endY:Number, numArcs:Number, waveHeight:Number, startPeak:Boolean = true, vars:Object = null):Animation
		{
			var startPoint:Point = new Point( startX, startY );
			var endPoint:Point = new Point( endX, endY );
			
			var dx:Number = endX - startX;
			dx = dx/(numArcs+1);
			var dy:Number = endY - startY;
			dy = dy/(numArcs+1);
			
			var pathPoints:Array = new Array(2 + numArcs);
			pathPoints[0] = startPoint;
			pathPoints[1 + numArcs] = endPoint;
			var i:int;
			
			var direction:Number = startPeak? 1 : -1;
			for(i=1; i<=numArcs; i++)
			{
				var currentPoint:Point = new Point(startX + dx*i, startY + direction*waveHeight/2 + dy);
				pathPoints[i] = currentPoint;
				direction = direction*-1;
			}
			
			
			var bezierVars:Object = {"values":pathPoints, "type":"thru", "curviness": 1, "ease": "Linear.easeNone"};
		    //bezierVars["autoRotate"] = ["x","y","rotation",0,true];
			if(vars == null)
			{
				vars =  {"bezier":bezierVars};
			}
			else
			{
				vars["bezier"] = bezierVars;
			}
			var tween:Animation = TweenLite.to( target, duration, vars );
			return tween;
		}
		
		static public function arcTo( target:Object, duration:Number,
									  startX:Number, startY:Number, endX:Number, endY:Number,
									  vars:Object,
									  onUpdate:Function = null,
									  curvePercent:Number = 0.5,
									  curvePercentVariance:Number = 0.1,
									  initialAngleOffset:Number = 0.0,
									  initialAngleVariance:Number = 1.5,
									  autoRotate:Boolean = false,
									  easeType:String = null):Animation {
			var startPoint:Point = new Point( startX, startY );
			var dx:Number = endX - startX;
			var dy:Number = endY - startY;
			var angle:Number = Math.atan2(dy,dx) + initialAngleOffset;
			var d:Number = Math.sqrt(dx*dx + dy*dy);
			if (initialAngleVariance != 0.0) {
				angle += (Math.random()*2-1)*initialAngleVariance;
			}
			dx = Math.cos(angle) * d;
			dy = Math.sin(angle) * d;
			if (curvePercentVariance != 0.0) {
				curvePercent += (Math.random()*2-1)*curvePercentVariance;
			}
			var midPoint:Point = new Point( startX + dx*curvePercent, startY + dy*curvePercent );
			var endPoint:Point = new Point( endX, endY );
			var pathPoints:Array = [startPoint, midPoint, endPoint];
			var bezierVars:Object;
			if(easeType == null)
				bezierVars = {"values":pathPoints, "type":"quadratic"};
			else
				bezierVars = {"values":pathPoints, "type":"quadratic", "ease": easeType};
			
			if (autoRotate) {
				bezierVars["autoRotate"] = ["x","y","rotation",0,true]
			}
			if (vars == null) {
				vars =  {"bezier":bezierVars};
			} else {
				vars["bezier"] = bezierVars;
			}
			var tween:Animation = TweenLite.to( target, duration, vars );
			return tween;
		}
		
		static public function getTotalScale( object:DisplayObject, point:Point = null ):Point {
			if (point==null) {
				point = new Point(object.scaleX,object.scaleY);
			} else {
				point.setTo( object.scaleX,object.scaleY);
			}
			object = object.parent;
			while (object) {
				point.x *= object.scaleX;
				point.y *= object.scaleY;
				object = object.parent;
			}
			return point;
		}
		
		static public function setPivotPoint( object:DisplayObject, pivotX:Number, pivotY:Number ):DisplayObject {
			var width:Number = object.width;
			var height:Number = object.height;
			if ( object is FeathersControl ) {
				width /= object.scaleX;
				height /= object.scaleY;
			}
			object.pivotX = width * pivotX;
			object.pivotY = height * pivotY;
			return object;
		}
		
		/**
		 * Make a deep clone of a GreenSock Animation, optionally supplying a new target
		 */
		public static function clone(source:Animation, newTarget:Object = null):Animation {
			var numChildren:int;
			var child:Animation;
			var children:Array;
			var i:int;
			var oldStartTime:Number;
			var tll:TimelineLite = source as TimelineLite;
			if (tll != null) {
				oldStartTime = tll.startTime();
				var newTll:TimelineLite;
				var tlm:TimelineMax = source as TimelineMax;
				if (tlm != null) {
					var newTlm:TimelineMax = new TimelineMax();
					newTll = newTlm;
					newTlm.repeat( tlm.repeat() );
					newTlm.repeatDelay( tlm.repeatDelay() );
					newTlm.reversed( tlm.reversed() );
					newTlm.yoyo( tlm.yoyo() );
				} else {
					newTll = new TimelineLite();
				}
				newTll.vars = copyVars( tll.vars );
				newTll.autoRemoveChildren = tll.autoRemoveChildren;
				newTll.delay( tll.delay() );
				newTll.paused( tll.paused() );
				newTll.timeScale( tll.timeScale() );
				newTll.startTime( tll.startTime() );
				newTll.paused( tll.paused() );
				children = tll.getChildren();
				numChildren = children.length;
				var newChildren:Array = []
				for (i=0; i<numChildren; ++i) {
					child = AnimationUtil.clone( children[i], newTarget );
					newChildren.push( child );
				}
				newTll.add( newChildren, 0, TweenAlign.START );
				newTll.startTime(oldStartTime);
				return newTll;
			}
			var tm:TweenMax = source as TweenMax;
			if (tm != null) {
				oldStartTime = tl.startTime();
				var newTm:TweenMax = new TweenMax( newTarget ? newTarget : tm.target, tm.duration(), copyVars(tm.vars) );
				newTm.paused( tm.paused() );
				newTm.startTime(oldStartTime);
				return newTm;
			}
			var tl:TweenLite = source as TweenLite;
			if (tl != null) {
				oldStartTime = tl.startTime();
				var newTl:TweenLite= new TweenLite( newTarget ? newTarget : tl.target, tl.duration(), copyVars(tl.vars) );
				newTl.paused( tl.paused() );
				newTl.startTime(oldStartTime);
				return newTl;
			}
			return null;
		}
		
		private static function copyVars(source:Object):Object {
			var copy:Object = {};
			for (var field:String in source) {
				copy[field] = source[field];
			}
			return copy;
		}
		
		// Set an object's position and scale in screen space to be that of another object
		public static function moveTo(target:DisplayObject, to:DisplayObject, scale:Boolean = true):void {
			HELPER_POINT_1.setTo( to.x, to.y );
			to.parent.localToGlobal( HELPER_POINT_1, HELPER_POINT_1 );
			target.parent.globalToLocal( HELPER_POINT_1, HELPER_POINT_1 );
			target.x = HELPER_POINT_1.x;
			target.y = HELPER_POINT_1.y;

			if (scale) {
				getTotalScale( to, HELPER_POINT_1 );
				getTotalScale( target, HELPER_POINT_2 );
				target.scaleX = HELPER_POINT_1.x / (HELPER_POINT_2.x / target.scaleX);
				target.scaleY = HELPER_POINT_1.y / (HELPER_POINT_2.y / target.scaleY);
			}
		}
		
		// based on a given name, get the BaseProcessManager
		// ... if given special key name "global", it will return the singleton
		// ... if given special key name "view", it return the parent BaseView's BaseProcessManager
		public static function getProcessManager(name:String, dsp:DisplayObject = null):BaseProcessManager {
			var pMan:BaseProcessManager = null;
			if (name == "global") {
				return ProcessManager.instance;
			} 
			else if (name == "view") {				
				if (!dsp)
				{
					trace("ERROR! AnimationUtil::getProcessManager(" + arguments + "): given DisplayObject cannot be null!");
					return null;
				}
								
				// if this DisplayObject hasn't been populated yet, early out
				var parent:DisplayObjectContainer = dsp.parent;
				if (!parent)
					return null;
				
				// walk up the chain and find the BaseView
				while (parent && !(parent is BaseView)) {
					parent = parent.parent;
				}
				if (parent)
					pMan = (parent as BaseView).viewProcessManager;
				else {
					// no BaseView found in lineage; early out
					trace("ERROR! AnimationUtil::getProcessManager(" + arguments + "): could not find any parent that is a BaseView!");
					return null;
				}
			}
			else
				pMan = ProcessManager.instance.getMiniProcessManager(name);
			return pMan;
		}
	}
	
}