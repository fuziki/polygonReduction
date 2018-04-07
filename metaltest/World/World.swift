//
//  World.swift
//  metaltest
//


import Foundation
import simd
import MetalKit

class Camera {
    weak var world: World!
    private var rot: Float = 0
    private var sgn: Float = 0.01
    init(world myworld: World) {
        world = myworld
    }
    func update() {
//        rot += sgn
//        if abs(rot) > 0.8 { sgn *= -1 }
        world.mtlEz.lookAt(from: float3(0, 1.0, -2.3), direction: normalize(float3(sin(rot), -1, 2)), up: float3(0, 1, 0))
    }
}

class World {
    weak var mtlEz: MetalEz!
    private var camera: Camera!
    private var realship: Realship!
    private var cube: Cube!
    init(metalEz: MetalEz) {
        mtlEz = metalEz
        camera = Camera(world: self)
        realship = Realship(world: self)
        cube = Cube(world: self)
    }
    func update() {
        camera.update()
        realship.update()
        cube.update()
    }
    func draw(type: MetalEzRenderingEngine.RendererType) {
        switch type {
        case .mesh: break
//            cube.draw(type: type)

        case .skinning: break

        case .mesh_add: break

        case .mesh_nonlighting: break
//            realship.draw(type: type)

        case .targetMarker: break

        case .points: break

        case .explosion: break

        case .sea: break
            
        case .line:
            realship.draw(type: type)
        
        default: break
        }
    }
}


