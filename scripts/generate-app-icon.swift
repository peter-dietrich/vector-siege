import AppKit
import Foundation

// Deterministic, original macOS app icons. Generated at build time; no remote images.
let game = CommandLine.arguments[1]
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let colors: [String: (NSColor,NSColor,String)] = [
 "fun-city": (.systemPink,.systemOrange,"arcade.stick"),
 "vector-drift": (.cyan,.blue,"paperplane.fill"),
 "vector-siege": (.systemGreen,.green,"shield.lefthalf.filled"),
 "vector-vortex": (.magenta,.purple,"hurricane"),
 "vector-swarm": (.cyan,.magenta,"sparkles"),
 "vector-barrage": (.orange,.cyan,"scope"),
 "vector-soar": (.cyan,.white,"airplane"),
 "vector-aces": (.systemYellow,.orange,"airplane.circle.fill")
]
let (primary,secondary,symbol) = colors[game] ?? colors["fun-city"]!
func draw(_ points:[CGPoint],color:NSColor,width:CGFloat,closed:Bool=false) {
 guard let first=points.first else{return}
 let p=NSBezierPath();p.move(to:first)
 for v in points.dropFirst(){p.line(to:v)}
 if closed{p.close()}
 p.lineWidth=width;p.lineJoinStyle = .round
 color.setStroke();p.stroke()
}
func render(_ pixels:Int) -> Data {
 guard let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:pixels,pixelsHigh:pixels,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
 let ctx=NSGraphicsContext(bitmapImageRep:rep) else {fatalError("Icon bitmap unavailable")}
 NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=ctx
 let scale=NSAffineTransform();scale.scale(by:CGFloat(pixels)/512);scale.concat()
 let bounds=CGRect(x:12,y:12,width:488,height:488)
 let outline=NSBezierPath(roundedRect:bounds,xRadius:110,yRadius:110)
 outline.addClip()
 NSGradient(starting:NSColor(calibratedRed:0.07,green:0.11,blue:0.21,alpha:1),
 ending:NSColor(calibratedRed:0.015,green:0.025,blue:0.08,alpha:1))!.draw(in:outline,angle:65)
 for i in 0..<9{
  let x=CGFloat(i)*60
  draw([CGPoint(x:x,y:15),CGPoint(x:x,y:497)],color:.white.withAlphaComponent(0.045),width:1)
 }
 let glow=NSShadow();glow.shadowColor=primary.withAlphaComponent(0.8);glow.shadowBlurRadius=24;glow.set()
 outline.lineWidth=12;primary.setStroke();outline.stroke()
 NSShadow().set()
 if game == "vector-vortex" {
  for r in [46,94,141,182] {
   let p=NSBezierPath(ovalIn:CGRect(x:256-r,y:256-r,width:r*2,height:r*2))
   p.lineWidth=r==182 ? 10 : 4; primary.withAlphaComponent(0.9).setStroke();p.stroke()
  }
  for i in 0..<12 {
   let a=Double(i)*Double.pi/6
   draw([CGPoint(x:256,y:256),CGPoint(x:256+cos(a)*182,y:256+sin(a)*182)],color:secondary.withAlphaComponent(0.4),width:3)
  }
 } else if game == "vector-swarm" {
  for row in 0..<3 {for col in 0..<4 {
   let x=CGFloat(147+col*72),y=CGFloat(373-row*75)
   draw([CGPoint(x:x-27,y:y-13),CGPoint(x:x,y:y+20),CGPoint(x:x+27,y:y-13)],color:row==0 ? .orange:secondary,width:7)
  }}
  draw([CGPoint(x:256,y:182),CGPoint(x:201,y:112),CGPoint(x:256,y:146),CGPoint(x:311,y:112)],color:primary,width:9)
 } else if game == "vector-drift" {
  draw([CGPoint(x:256,y:393),CGPoint(x:156,y:141),CGPoint(x:256,y:207),CGPoint(x:356,y:141)],color:primary,width:12,closed:true)
  for (x,y,r) in [(132.0,325.0,43.0),(392.0,272.0,34.0),(385.0,136.0,18.0)] {
   let p=NSBezierPath(ovalIn:CGRect(x:x-r,y:y-r,width:r*2,height:r*2));p.lineWidth=7
   secondary.setStroke();p.stroke()
  }
 } else if game == "vector-siege" {
  let t=NSBezierPath(roundedRect:CGRect(x:124,y:174,width:268,height:105),xRadius:25,yRadius:25)
  t.lineWidth=10;primary.setStroke();t.stroke()
  for x in stride(from:165,through:347,by:60) {
   let p=NSBezierPath(ovalIn:CGRect(x:x-18,y:180,width:36,height:36))
   p.lineWidth=5;primary.setStroke();p.stroke()
  }
  draw([CGPoint(x:180,y:276),CGPoint(x:212,y:346),CGPoint(x:303,y:346),CGPoint(x:334,y:276)],color:primary,width:10)
  draw([CGPoint(x:266,y:321),CGPoint(x:416,y:371)],color:secondary,width:16)
 } else if game == "vector-barrage" {
  for x in stride(from:130,through:390,by:52) {
   let rect=NSBezierPath(rect:CGRect(x:x-17,y:122,width:35,height:CGFloat(47+(x%65))))
   rect.lineWidth=4;secondary.setStroke();rect.stroke()
  }
  for x in [160.0,256.0,353.0] {draw([CGPoint(x:x,y:181),CGPoint(x:256,y:371)],color:primary,width:7)}
  let ball=NSBezierPath(ovalIn:CGRect(x:221,y:337,width:70,height:70));ball.lineWidth=10;primary.setStroke();ball.stroke()
 } else if game == "fun-city" {
  let cab=NSBezierPath(roundedRect:CGRect(x:107,y:166,width:298,height:255),xRadius:31,yRadius:31)
  cab.lineWidth=9;primary.setStroke();cab.stroke()
  let screen=NSBezierPath(roundedRect:CGRect(x:140,y:259,width:231,height:127),xRadius:9,yRadius:9)
  screen.lineWidth=6;secondary.setStroke();screen.stroke()
  draw([CGPoint(x:256,y:355),CGPoint(x:207,y:280),CGPoint(x:256,y:306),CGPoint(x:305,y:280)],color:.cyan,width:7)
  draw([CGPoint(x:172,y:230),CGPoint(x:172,y:195)],color:primary,width:10)
  let coin=NSBezierPath(ovalIn:CGRect(x:231,y:116,width:50,height:50))
  coin.lineWidth=9;secondary.setStroke();coin.stroke()
 } else {
  let image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)!
   .withSymbolConfiguration(.init(pointSize:287,weight:.medium))!
  image.draw(in:CGRect(x:112,y:126,width:288,height:288))
  draw([CGPoint(x:132,y:118),CGPoint(x:203,y:118)],color:secondary,width:7)
  draw([CGPoint(x:310,y:118),CGPoint(x:380,y:118)],color:secondary,width:7)
 }
 ctx.flushGraphics();NSGraphicsContext.restoreGraphicsState()
 return rep.representation(using:.png,properties:[:])!
}
let folder=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("fun-city-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
defer{try? FileManager.default.removeItem(at:folder)}
for (name,size) in [("icon_16x16.png",16),("icon_16x16@2x.png",32),
 ("icon_32x32.png",32),("icon_32x32@2x.png",64),
 ("icon_128x128.png",128),("icon_128x128@2x.png",256),
 ("icon_256x256.png",256),("icon_256x256@2x.png",512),
 ("icon_512x512.png",512),("icon_512x512@2x.png",1024)] {
 try render(size).write(to:folder.appendingPathComponent(name))
}
try FileManager.default.createDirectory(at:output.deletingLastPathComponent(),withIntermediateDirectories:true)
let task=Process();task.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil")
task.arguments=["-c","icns",folder.path,"-o",output.path]
try task.run();task.waitUntilExit()
guard task.terminationStatus == 0 else {throw NSError(domain:"IconGeneration",code:Int(task.terminationStatus))}
print("Generated \(game) icon")
