//
//  Realship
//  metaltest
//


import Foundation
import simd
import MetalKit

extension float3 {
    var toFloat4: float4 {
        return float4(self.x, self.y, self.z, 1)
    }
}

class Realship {
    weak var world: World!
    private var drawers = [MetalEz.MeshDrawer]()
    private var rot: Float = 0.0
    var models = [HalfEdgeStructure.Model]()
    var mdlBffs = [MTLBuffer]()
//    var mdlBff2: MTLBuffer
//    var mdlBff2: MTLBuffer
    var vertexCounts = [Int]()
//    var vertexCount2: Int = 0
    init(world myworld: World) {
        world = myworld
//        let model3 = HalfEdgeController.LoadModel(mtlEz: world.mtlEz, name: "myball3968", reduction: 2000)
//        let model4 = HalfEdgeController.LoadModel(mtlEz: world.mtlEz, name: "myball3968", reduction: 0)
/*        let model1 = HalfEdgeController.LoadModel(mtlEz: world.mtlEz, name: "myball", reduction: 0)
        let model2 = HalfEdgeController.LoadModel(mtlEz: world.mtlEz, name: "myball", reduction: 0)
        let model3 = HalfEdgeController.LoadModel(mtlEz: world.mtlEz, name: "myball", reduction: 0)
        let model4 = HalfEdgeController.LoadModel(mtlEz: world.mtlEz, name: "myball", reduction: 0)*/
        models.append(HalfEdgeStructure.LoadModel(mtlEz: world.mtlEz, name: "realship", reduction: 2300))
        models.append(HalfEdgeStructure.LoadModel(mtlEz: world.mtlEz, name: "realship", reduction: 0))
//        models.append(model3)
//        models.append(model4)

//        for i in 0..<100 {
//            model.edgeCollapse(halfEdge: model.faces[1].halfEdge )
//        }
        for model in models {
            let tex = world.mtlEz.loader.loadTexture(name: "shipDiffuse", type: "png")
            let mesh = world.mtlEz.loader.loadMesh(name: "realship")
            let d = MetalEz.MeshDrawer(mtlEz: world.mtlEz ,mesh: mesh, texture: tex)
            drawers.append(d)

            var mdlBff = world.mtlEz.line.makeVertexBuffer(count: model.polygons.count * 3 * 2)
            var pnts = [MetalEzLineRendererPoint]()
            print("faces count is ", model.polygons.count)
            for (_, fullEdge) in model.fullEdges {
                pnts.append(MetalEzLineRendererPoint(point: fullEdge.startVertex.toFloat4))
                pnts.append(MetalEzLineRendererPoint(point: fullEdge.endVertex.toFloat4))
            }
            world.mtlEz.line.set(points: pnts, buffer: &mdlBff)
            mdlBffs.append(mdlBff)
            let vertexCount = model.polygons.count * 3 * 2
            vertexCounts.append(vertexCount)
        }
        
/*        for (key, face) in model.faces {
            var edge = face.halfEdge
            for _ in 0..<3 {
                pnts.append(MetalEzLineRendererPoint(point: edge.vertex.position.toFloat4))
                pnts.append(MetalEzLineRendererPoint(point: edge.nextHalfEdge.vertex.position.toFloat4))
                edge = edge.nextHalfEdge
            }
        }*/
        
        
/*
        mdlBff2 = world.mtlEz.line.makeVertexBuffer(count: model2.faces.count * 3 * 2)
        var pnts2 = [MetalEzLineRendererPoint]()
        print("faces count is ", model2.faces.count)
        for (_, fullEdge) in model2.fullEdges {
            pnts2.append(MetalEzLineRendererPoint(point: fullEdge.startVertex.toFloat4))
            pnts2.append(MetalEzLineRendererPoint(point: fullEdge.endVertex.toFloat4))
        }
/*        for (key, face) in model2.faces {
            var edge = face.halfEdge
            for _ in 0..<3 {
                pnts2.append(MetalEzLineRendererPoint(point: edge.vertex.position.toFloat4))
                pnts2.append(MetalEzLineRendererPoint(point: edge.nextHalfEdge.vertex.position.toFloat4))
                edge = edge.nextHalfEdge
            }
        }*/
        world.mtlEz.line.set(points: pnts2, buffer: &mdlBff2)
        vertexCount2 = model2.faces.count * 3 * 2*/
        
    }
    func update() {
        rot += 0.5
        var mat = matrix_identity_float4x4
        mat = matrix_multiply(mat, Utils.translation(float3(0.9, 0.0, 0.0)))
        mat = matrix_multiply(mat, Utils.rotation_x(radians: toRad(fromDeg: -30)))
        mat = matrix_multiply(mat, Utils.rotation_y(radians: toRad(fromDeg: rot)))
//        mat = matrix_multiply(mat, Utils.rotation_y(radians: toRad(fromDeg: 180)))
        drawers[0].set(modelMatrix: mat)
        
        var mat1 = matrix_identity_float4x4
        mat1 = matrix_multiply(mat1, Utils.translation(float3(-0.9, 0.0, 0.0)))
        mat1 = matrix_multiply(mat1, Utils.rotation_x(radians: toRad(fromDeg: -30)))
        mat1 = matrix_multiply(mat1, Utils.rotation_y(radians: toRad(fromDeg: rot)))
//        mat1 = matrix_multiply(mat1, Utils.rotation_y(radians: toRad(fromDeg: 180)))
        drawers[1].set(modelMatrix: mat1)
        
/*        var mat2 = matrix_identity_float4x4
        mat2 = matrix_multiply(mat2, Utils.translation(float3(-0.3, 0.4, 0.0)))
        //        mat = matrix_multiply(mat, Utils.rotation_x(radians: toRad(fromDeg: 10)))
        mat2 = matrix_multiply(mat2, Utils.rotation_y(radians: toRad(fromDeg: rot)))
        mat2 = matrix_multiply(mat2, Utils.rotation_y(radians: toRad(fromDeg: 180)))
        drawers[2].set(modelMatrix: mat2)
        
        var mat3 = matrix_identity_float4x4
        mat3 = matrix_multiply(mat3, Utils.translation(float3(-0.9, 0.4, 0.0)))
        //        mat = matrix_multiply(mat, Utils.rotation_x(radians: toRad(fromDeg: 10)))
        mat3 = matrix_multiply(mat3, Utils.rotation_y(radians: toRad(fromDeg: rot)))
        mat3 = matrix_multiply(mat3, Utils.rotation_y(radians: toRad(fromDeg: 180)))
        drawers[3].set(modelMatrix: mat3)*/
        

    }
    func draw(type: MetalEzRenderingEngine.RendererType) {
        if type == .mesh_nonlighting {
//            drawer.draw()
        }
        if type == .line {
            for i in 0..<models.count {
                world.mtlEz.line.draw(vaertex: mdlBffs[i],
                                      frameUniformBuffer: drawers[i].frameUniformBuffer,
                                      count: vertexCounts[i])

            }
/*            world.mtlEz.line.draw(vaertex: mdlBff,
                                  frameUniformBuffer: drawer.frameUniformBuffer,
                                  count: vertexCount)
            
            world.mtlEz.line.draw(vaertex: mdlBff2,
                                  frameUniformBuffer: drawer2.frameUniformBuffer,
                                  count: vertexCount2)*/
        }
    }
}


/*

class Realship {
    weak var world: World!
    private var drawer: MetalEz.MeshDrawer
    private var rot: Float = 0.0
    init(world myworld: World) {
        world = myworld
        let tex = world.mtlEz.loader.loadTexture(name: "shipDiffuse", type: "png")
        let mesh = world.mtlEz.loader.loadMesh(name: "realship")
        drawer = MetalEz.MeshDrawer(mtlEz: world.mtlEz ,mesh: mesh, texture: tex)
    }
    func update() {
        rot += 1
        var mat = matrix_identity_float4x4
        mat = matrix_multiply(mat, Utils.translation(float3(2, -1, 3)))
        mat = matrix_multiply(mat, Utils.rotation_y(radians: toRad(fromDeg: rot)))
        drawer.set(modelMatrix: mat)
    }
    func draw(type: MetalEzRenderingEngine.RendererType) {
        if type == .mesh_nonlighting {
            drawer.draw()
        }
    }
}

*/




