
//
//  MetalEz.swift
//  metaltest
//


import MetalKit

protocol MetalEzClassDelegate {
    func update()
    func draw(type: MetalEzRenderingEngine.RendererType)
}

class MetalEz: NSObject, MTKViewDelegate {
    var delegate: MetalEzClassDelegate?
    var mtkView: MTKView!
    var device: MTLDevice!
    
    private var commandQueue: MTLCommandQueue!
    private var depthStencilState: MTLDepthStencilState!
    private var depthStencilStateForBlending: MTLDepthStencilState!
    private let semaphore = DispatchSemaphore(value: 1)

    private var mtlRenderPipelineStateArray = [(MetalEzRenderingEngine.RendererType, MTLRenderPipelineState)]()
    private var mtlRenderPipelineStateArrayForBlending = [(MetalEzRenderingEngine.RendererType, MTLRenderPipelineState)]()

    
    // MARK: metal data for draw objects
    var mtlRenderCommandEncoder:MTLRenderCommandEncoder!
    var cameraMatrix = matrix_identity_float4x4 //use by drawers, camera matrix update by look at
    var projectionMatrix = matrix_float4x4()    //use by drawers
    
    var mtlEzRenderingEngineArray = [MetalEzRenderingEngine]()
    var mesh: MetalEzMmeshRenderer!
    var loader: MetalEzLoader!
    var explosionEmitter: MetalEzExplosionRenderer!
    var line: MetalEzLineRenderer!

    // MARK: metal initializer
    func setupMetal(mtkView view: MTKView) {
        print("setupMetal")
        mtkView = view
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()
        
        mtkView.sampleCount = 4
        mtkView.depthStencilPixelFormat = .depth32Float_stencil8
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColorMake(0.2, 0.2, 0.2, 1.0)
        mtkView.device = device
        mtkView.delegate = self

        projectionMatrix = Utils.perspective(toRad(fromDeg: 75),
                                              aspectRatio: Float(mtkView.drawableSize.width / mtkView.drawableSize.height),
                                              zFar: 255,
                                              zNear: 0.1)

        
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDescriptor)

        let depthDescriptorForBlending = MTLDepthStencilDescriptor()
        depthDescriptorForBlending.depthCompareFunction = .less
        depthDescriptorForBlending.isDepthWriteEnabled = false
        depthStencilStateForBlending = device.makeDepthStencilState(descriptor: depthDescriptorForBlending)
        
        var mtlRenderPipelineStateDictionary = Dictionary<MetalEzRenderingEngine.RendererType, MTLRenderPipelineState>()

        loader = MetalEzLoader(MetalEz: self)
        mesh = MetalEzMmeshRenderer(MetalEz: self, pipelineDic: &mtlRenderPipelineStateDictionary)
        explosionEmitter = MetalEzExplosionRenderer(MetalEz: self, pipelineDic: &mtlRenderPipelineStateDictionary)
        line = MetalEzLineRenderer(MetalEz: self, pipelineDic: &mtlRenderPipelineStateDictionary)
        
        for (key,val) in mtlRenderPipelineStateDictionary {
            print("dic: \(key), \(val.label ?? "non")")
            if val.label != nil {
                if (val.label?.contains(MetalEzRenderingEngine.blendingIsEnabled))! {
                    mtlRenderPipelineStateArrayForBlending.append((key, val))
                    print("add belnding")
                } else {
                    mtlRenderPipelineStateArray.append((key, val))
                    print("add nomal")
                }
            } else {
                mtlRenderPipelineStateArray.append((key, val))
                print("add nomal")
            }
        }
    }
    
    // MARK: set camera
    func lookAt(from: float3, direction: float3, up: float3) {
        cameraMatrix = Utils.lookAt(from: from, direction: direction, up: up)
    }
    // MARK: MTKViewDelegate
    func draw(in view: MTKView) {
        self.delegate?.update()
        autoreleasepool {
            semaphore.wait()
            let commandBuffer = commandQueue.makeCommandBuffer()
            mtlRenderCommandEncoder = commandBuffer?.makeRenderCommandEncoder(descriptor: view.currentRenderPassDescriptor!)
            mtlRenderCommandEncoder.pushDebugGroup("Render Object")
            mtlRenderCommandEncoder.setDepthStencilState(depthStencilState)

            mtlRenderPipelineStateArray.forEach { (key,val) in
                mtlRenderCommandEncoder.setRenderPipelineState(val)
                self.delegate?.draw(type: key)
                print("draw \(key)")
            }
            mtlRenderCommandEncoder.setDepthStencilState(depthStencilStateForBlending)
            mtlRenderPipelineStateArrayForBlending.forEach { (key,val) in
                mtlRenderCommandEncoder.setRenderPipelineState(val)
                self.delegate?.draw(type: key)
                print("draw blending \(key)")
            }

            mtlRenderCommandEncoder.popDebugGroup()
            mtlRenderCommandEncoder.endEncoding()
            commandBuffer?.present(view.currentDrawable!)
            commandBuffer?.addCompletedHandler { _ in
                self.semaphore.signal()
            }
            commandBuffer?.commit()
        }
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
    }
}










